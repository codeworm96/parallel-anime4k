#include "anime4k_cuda.h"
#include "instrument.h"

#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <cuda.h>
#include <cuda_runtime.h>

#define REGIONW 28
#define REGIONH 28
#define PADDING 2
#define THREADW (REGIONW+2*PADDING)
#define THREADH (REGIONH+2*PADDING)

#define cudaCheckError(ans)  cudaAssert((ans), __FILE__, __LINE__);
inline void cudaAssert(cudaError_t code, const char *file, int line, bool abort=true)
{
   if (code != cudaSuccess)
   {
      fprintf(stderr, "CUDA Error: %s at %s:%d\n",
        cudaGetErrorString(code), file, line);
        if (abort) exit(code);
    }
 }

__constant__ Param cudaParam;
unsigned char *cudaImage;
unsigned char *cudaResult;
__global__ void kernel(unsigned char *src, unsigned char *dst);


Anime4kCuda::Anime4kCuda(
    unsigned int width, unsigned int height, unsigned char *image,
    unsigned int new_width, unsigned int new_height)
{
    param.src_width = width;
    param.src_height = height;
    param.dst_width = new_width;
    param.dst_height = new_height;
    param.src_bytes = 4*width*height*sizeof(unsigned char);
    param.dst_bytes = 4*new_width*new_height*sizeof(unsigned char);
    param.strength_preprocessing = min((float)new_width / width / 6.0, 1.0);
    param.strength_push = min((float)new_width / width / 2.0, 1.0);
    image_ = image;
    result_ = new unsigned char[param.dst_bytes];

    cudaMalloc(&cudaImage, param.src_bytes);
    cudaMalloc(&cudaResult, param.dst_bytes);
    cudaMemcpyToSymbol(cudaParam, &param, sizeof(Param));
}

void Anime4kCuda::run()
{
    dim3 gridDim((param.dst_width+REGIONW-1)/REGIONW, 
                (param.dst_height+REGIONH-1)/REGIONH);
    dim3 blockDim(THREADW,THREADH);
    cudaMemcpy(cudaImage, image_, param.src_bytes,cudaMemcpyHostToDevice);
    kernel<<<gridDim,blockDim>>>(cudaImage,cudaResult);
    cudaMemcpy(result_, cudaResult, param.dst_bytes,cudaMemcpyDeviceToHost);

}

Anime4kCuda::~Anime4kCuda()
{
    delete [] result_;
    cudaFree(cudaImage);
    cudaFree(cudaResult);
}

/**  cuda code **/

__device__ __inline__ float 
interpolate(unsigned char tl, unsigned char tr,
    unsigned char bl, unsigned char br, float f, float g)
{
    float t = ((float)tl/255.0)*(1.0-f)+((float)tr/255.0)*f;
    float b = ((float)bl/255.0)*(1.0-f)+((float)br/255.0)*f;
    return t*(1.0-g)+b*g;
}

__device__ void
enlarge(unsigned char *image, float *enlarged, bool qualified)
{
    int threadId = threadIdx.y*blockDim.x+threadIdx.x;
    int pixelX = blockIdx.x*REGIONW+threadIdx.x-PADDING;
    int pixelY = blockIdx.y*REGIONH+threadIdx.y-PADDING;
    int src_width = cudaParam.src_width;
    int src_height = cudaParam.src_height;
    int dst_width = cudaParam.dst_width;
    int dst_height = cudaParam.dst_height;

    
    if (qualified) {
        // map padded pixel to valid pixel
        if (pixelX<0) pixelX = 0;
        if (pixelX>=dst_width) pixelX=dst_width-1;
        if (pixelY<0) pixelY = 0;
        if (pixelY>=dst_height) pixelY=dst_height-1;
    
        float x = (float) (pixelX * src_width) / (float) dst_width;
        float y = (float) (pixelY * src_height) / (float) dst_height;
        int tlx = floor(x);
        int tly = floor(y);
        float f = x - tlx;
        float g = y - tly;
    
        int tl = 4 * (tly*src_width+tlx);
        int tr = tl + 4;
        int bl = tl + 4*src_width;
        int br = bl + 4;
    
        enlarged[3*threadId] = interpolate(image[tl],image[tr],image[bl],image[br],f,g);
        enlarged[3*threadId+1] = interpolate(image[tl+1],image[tr+1],image[bl+1],image[br+1],f,g);
        enlarged[3*threadId+2] = interpolate(image[tl+2],image[tr+2],image[bl+2],image[br+2],f,g);
    }
    __syncthreads();
}


__device__ void
compute_luminance(float *image, float *luminace, bool qualified) 
{
    if (qualified) {
        int threadId = threadIdx.y*blockDim.x+threadIdx.x;
        luminace[threadId] = (image[3*threadId]*2+image[3*threadId+1]*3 
                                + image[3*threadId]) / 6.0;
    }
    __syncthreads();
}

__device__ __inline__ float 
min3v(float a, float b, float c) {
    return min(min(a, b), c);
}

__device__ __inline__ float 
max3v(float a, float b, float c) {
    return max(max(a, b), c);
}

__device__ __inline__ void 
get_largest(float strength, float *image, float *lum,
    float color[4], int cc, int a, int b, int c)
{
    float new_lum = lum[cc] * (1 - strength) +
        ((lum[a] + lum[b] + lum[c]) / 3) * strength;
    
    if (new_lum > color[3]) {
        color[0] = image[cc * 3] * (1 - strength) +
            ((image[a * 3] + image[b * 3] + image[c * 3]) / 3) * strength;
        color[1] = image[cc * 3 + 1] * (1 - strength) +
            ((image[a * 3 + 1] + image[b * 3 + 1] + image[c * 3 + 1]) / 3) * strength;
        color[2] = image[cc * 3 + 2] * (1 - strength) +
            ((image[a * 3 + 2] + image[b * 3 + 2] + image[c * 3 + 2]) / 3) * strength;
        color[3] = new_lum;
    }
}



__device__ __inline__ void
preprocess(float *image, float *lum, float *preprocessed, bool qualified)
{
    int threadId = threadIdx.y*blockDim.x+threadIdx.x;

    float color[4];

    if (qualified) {
        color[0] = image[3 * threadId];
        color[1] = image[3 * threadId + 1];
        color[2] = image[3 * threadId + 2];
        color[3] = lum[threadId];
        
        int cc_ix = threadId;
        int r_ix = cc_ix + 1;
        int l_ix = cc_ix - 1;
        int t_ix = cc_ix - blockDim.x;
        int tl_ix = t_ix - 1;
        int tr_ix = t_ix + 1;
        int b_ix = cc_ix + blockDim.x;
        int bl_ix = b_ix - 1;
        int br_ix = b_ix + 1;

        float strength = cudaParam.strength_preprocessing;
        float cc = lum[cc_ix];
        float r = lum[r_ix];
        float l = lum[l_ix];
        float t = lum[t_ix];
        float tl = lum[tl_ix];
        float tr = lum[tr_ix];
        float b = lum[b_ix];
        float bl = lum[bl_ix];
        float br = lum[br_ix];

        /* pattern 0 and 4 */
        float maxDark = max3v(br, b, bl);
        float minLight = min3v(tl, t, tr);

        if (minLight > cc && minLight > maxDark) {
            get_largest(strength, image, lum, color,
                cc_ix, tl_ix, t_ix, tr_ix);
        } else {
            maxDark = max3v(tl, t, tr);
            minLight = min3v(br, b, bl);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength, image, lum, color,
                    cc_ix, br_ix, b_ix, bl_ix);
            }
        }

        /* pattern 1 and 5 */
        maxDark = max3v(cc, l, b);
        minLight = min3v(r, t, tr);

        if (minLight > maxDark) {
            get_largest(strength, image, lum, color,
                cc_ix, r_ix, t_ix, tr_ix);
        } else {
            maxDark = max3v(cc, r, t);
            minLight = min3v(bl, l, b);
            if (minLight > maxDark) {
                get_largest(strength, image, lum, color,
                    cc_ix, bl_ix, l_ix, b_ix);
            }
        }

        /* pattern 2 and 6 */
        maxDark = max3v(l, tl, bl);
        minLight = min3v(r, br, tr);

        if (minLight > cc && minLight > maxDark) {
            get_largest(strength, image, lum, color,
                cc_ix, r_ix, br_ix, tr_ix);
        } else {
            maxDark = max3v(r, br, tr);
            minLight = min3v(l, tl, bl);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength, image, lum, color,
                    cc_ix, l_ix, tl_ix, bl_ix);
            }
        }

        /* pattern 3 and 7 */
        maxDark = max3v(cc, l, t);
        minLight = min3v(r, br, b);

        if (minLight > maxDark) {
            get_largest(strength, image, lum, color,
                cc_ix, r_ix, br_ix, b_ix);
        } else {
            maxDark = max3v(cc, r, b);
            minLight = min3v(t, l, tl);
            if (minLight > maxDark) {
                get_largest(strength, image, lum, color,
                    cc_ix, t_ix, l_ix, tl_ix);
            }
        }

        preprocessed[3 * threadId] = color[0];
        preprocessed[3 * threadId + 1] = color[1];
        preprocessed[3 * threadId + 2] = color[2];
    }
    __syncthreads();
}


__device__ __inline__ float 
clamp(float x, float lower, float upper)
{
    return x < lower ? lower : (x > upper ? upper : x);
}

__device__ __inline__ void
compute_graident(float *lum, float *gradient, bool qualified)
{
    if (qualified) {
        int cc_ix = threadIdx.y*blockDim.x+threadIdx.x;
    
        /* [tl t tr]
         * [l cc  r]
         * [bl b br]
         */
        int t_ix = cc_ix - blockDim.x;
        int tl_ix = t_ix - 1;
        int tr_ix = t_ix + 1;
        int l_ix = cc_ix - 1;
        int r_ix = cc_ix + 1;
        int b_ix = cc_ix + blockDim.x;
        int bl_ix = b_ix - 1;
        int br_ix = b_ix + 1;
    
        float r = lum[r_ix];
        float l = lum[l_ix];
        float t = lum[t_ix];
        float tl = lum[tl_ix];
        float tr = lum[tr_ix];
        float b = lum[b_ix];
        float bl = lum[bl_ix];
        float br = lum[br_ix];
    
        /* Horizontal Gradient
        * [-1  0  1]
        * [-2  0  2]
        * [-1  0  1]
        */
        float xgrad = tr - tl + r + r - l - l + br - bl;
    
        /* Vertical Gradient
         * [-1 -2 -1]
         * [ 0  0  0]
         * [ 1  2  1]
         */
        float ygrad = bl - tl + b + b - t - t + br - tr;
    
        gradient[cc_ix] =
            1.0 - clamp(sqrt(xgrad * xgrad + ygrad * ygrad), 0.0, 1.0);
    }
    __syncthreads();
}


__device__ __inline__ void 
get_average(float strength, float *image, float color[3],
    int cc, int a, int b, int c)
{   
    color[0] = image[cc * 3] * (1.0 - strength) +
        ((image[a * 3] + image[b * 3] + image[c * 3]) / 3.0) * strength;
    color[1] = image[cc * 3 + 1] * (1.0 - strength) +
        ((image[a * 3 + 1] + image[b * 3 + 1] + image[c * 3 + 1]) / 3.0) * strength;
    color[2] = image[cc * 3 + 2] * (1.0 - strength) +
        ((image[a * 3 + 2] + image[b * 3 + 2] + image[c * 3 + 2]) / 3.0) * strength;
}


__device__ void
push(float *image, float *gradient, float *pushed, bool qualified)
{
    int threadId = threadIdx.y*blockDim.x+threadIdx.x;
    float color[3];

    if (qualified) {
        color[0] = image[3 * threadId];
        color[1] = image[3 * threadId + 1];
        color[2] = image[3 * threadId + 2];

        int cc_ix = threadId;
        int r_ix = cc_ix + 1;
        int l_ix = cc_ix - 1;
        int t_ix = cc_ix - blockDim.x;
        int tl_ix = t_ix - 1;
        int tr_ix = t_ix + 1;
        int b_ix = cc_ix + blockDim.x;
        int bl_ix = b_ix - 1;
        int br_ix = b_ix + 1;

        float strength = cudaParam.strength_push;
        float cc = gradient[cc_ix];
        float r = gradient[r_ix];
        float l = gradient[l_ix];
        float t = gradient[t_ix];
        float tl = gradient[tl_ix];
        float tr = gradient[tr_ix];
        float b = gradient[b_ix];
        float bl = gradient[bl_ix];
        float br = gradient[br_ix];

        if (min3v(tl, t, tr) > cc && min3v(tl, t, tr) > max3v(br, b, bl)) {
            get_average(strength, image, color,
                cc_ix, tl_ix, t_ix, tr_ix);
        } else if (min3v(br, b, bl) > cc && min3v(br, b, bl) > max3v(tl, t, tr)) {
            get_average(strength, image, color,
                cc_ix, br_ix, b_ix, bl_ix);
        } else if (min3v(r, t, tr) > max3v(cc, l, b)) {
            get_average(strength, image, color,
                cc_ix, r_ix, t_ix, tr_ix);
        } else if (min3v(bl, l, b) > max3v(cc, r, t)) {
            get_average(strength, image, color,
                cc_ix, bl_ix, l_ix, b_ix);
        } else if (min3v(r, br, tr) > cc && min3v(r, br, tr) > max3v(l, tl, bl)) {
            get_average(strength, image, color,
                cc_ix, r_ix, br_ix, tr_ix);
        } else if (min3v(l, tl, bl) > cc && min3v(l, tl, bl) > max3v(r, br, tr)) {
            get_average(strength, image, color,
                cc_ix, l_ix, tl_ix, bl_ix);    
        } else if (min3v(r, br, b) > max3v(cc, l, t)) {
            get_average(strength, image, color,
                cc_ix, r_ix, br_ix, b_ix);
        } else if (min3v(t, l, tl) > max3v(cc, r, b)) {
            get_average(strength, image, color,
                cc_ix, t_ix, l_ix, tl_ix);
        }

        pushed[3 * threadId] = color[0];
        pushed[3 * threadId + 1] = color[1];
        pushed[3 * threadId + 2] = color[2];
    }
    __syncthreads();
}

__device__ __inline__ unsigned char
quantize(float x) 
{
    int r = x * 255;
    return r < 0 ? 0 : (r > 255 ? 255 : r);
}

__device__ void
output(float *image, unsigned char *dst, bool qualified)
{
    int threadId = threadIdx.y*blockDim.x+threadIdx.x;
    int pixelX = blockIdx.x*REGIONW+threadIdx.x-PADDING;
    int pixelY = blockIdx.y*REGIONH+threadIdx.y-PADDING;
    int dst_width = cudaParam.dst_width;
    int pixelId = pixelY*dst_width+pixelX;

    if (qualified) {
        dst[4*pixelId] = quantize(image[3*threadId]);
        dst[4*pixelId+1] = quantize(image[3*threadId+1]);
        dst[4*pixelId+2] = quantize(image[3*threadId+2]);
        dst[4*pixelId+3] = 255;
    
        // dst[4*pixelId] = quantize(image[threadId]);
        // dst[4*pixelId+1] = quantize(image[threadId]);
        // dst[4*pixelId+2] = quantize(image[threadId]);
        // dst[4*pixelId+3] = 255;
    }
    __syncthreads();
}

__global__ void
kernel(unsigned char *src, unsigned char *dst)
{
    __shared__ float image[3*THREADW*THREADH];
    __shared__ float preprocessed[3*THREADW*THREADH];
    __shared__ float luminace[THREADW*THREADH];
    __shared__ float gradient[THREADW*THREADH];

    int pixelX = blockIdx.x*REGIONW+threadIdx.x-PADDING;
    int pixelY = blockIdx.y*REGIONH+threadIdx.y-PADDING;
    int dst_width = cudaParam.dst_width;
    int dst_height = cudaParam.dst_height;

    bool inside_image_nopaded = true;
    bool inside_image_padded = true;
    bool inside_thread_nopadded = true;
    bool inside_thread_onepadded = true;

    if (pixelX < 0 || pixelX >= dst_width ||
        pixelY < 0 || pixelY >= dst_height)
        inside_image_nopaded = false;

    if (pixelX >= dst_width+PADDING || pixelY >= dst_height+PADDING)
        inside_image_padded = false;

    if (threadIdx.x < PADDING || threadIdx.x >= blockDim.x - PADDING ||
        threadIdx.y < PADDING || threadIdx.y >= blockDim.y - PADDING) 
        inside_thread_nopadded = false;
    
    if (threadIdx.x < 1 || threadIdx.x >= blockDim.x - PADDING + 1 ||
        threadIdx.y < 1 || threadIdx.y >= blockDim.y - PADDING + 1) 
        inside_thread_onepadded = false;
    
    enlarge(src,image, inside_image_padded);
    compute_luminance(image, luminace, inside_image_padded);
    preprocess(image,luminace,preprocessed, inside_image_padded && inside_thread_onepadded);
    compute_luminance(image, luminace, inside_image_padded);
    compute_graident(luminace, gradient, inside_image_padded && inside_thread_onepadded);
    push(preprocessed, gradient, image, inside_image_nopaded && inside_thread_nopadded);
    output(image, dst, inside_image_nopaded && inside_thread_nopadded);
}



