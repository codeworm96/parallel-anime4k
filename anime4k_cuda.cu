#include "anime4k_cuda.h"
#include "instrument.h"

#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <cuda.h>
#include <cuda_runtime.h>

#define PADDING 2
#define THREADW 32
#define THREADH 32

__constant__ Param cudaParam;
unsigned char *cudaImage;
unsigned char *cudaResult;
float *imageBuff;
float *preprocessedBuff;
float *luminaceBuff;
float *gradientBuff;



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
    param.strength_preprocessing = min((float)new_width / width / 6.0f, 1.0f);
    param.strength_push = min((float)new_width / width / 2.0f, 1.0f);
    param.dst_width_padded = new_width+2*PADDING;
    param.dst_height_padded = new_height+2*PADDING;
    image_ = image;
    result_ = new unsigned char[param.dst_bytes];

    cudaMalloc(&cudaImage, param.src_bytes);
    cudaMalloc(&cudaResult, param.dst_bytes);
    cudaMalloc(&imageBuff, param.dst_width_padded*param.dst_height_padded*3*sizeof(float));
    cudaMalloc(&preprocessedBuff, param.dst_width_padded*param.dst_height_padded*3*sizeof(float));
    cudaMalloc(&luminaceBuff,param.dst_width_padded*param.dst_height_padded*sizeof(float));
    cudaMalloc(&gradientBuff,param.dst_width_padded*param.dst_height_padded*sizeof(float));
    cudaMemcpyToSymbol(cudaParam, &param, sizeof(Param));
}

Anime4kCuda::~Anime4kCuda()
{
    delete [] result_;
    cudaFree(cudaImage);
    cudaFree(cudaResult);
    cudaFree(imageBuff);
    cudaFree(preprocessedBuff);
    cudaFree(luminaceBuff);
    cudaFree(gradientBuff);
}

/**  cuda code **/

__device__ __inline__ float 
interpolate(unsigned char tl, unsigned char tr,
    unsigned char bl, unsigned char br, float f, float g)
{
    float minusf = 1.0f-f;
    float minusg = 1.0f-g;
    float t = ((float)tl*minusf+(float)tr*f)/255.0f;
    float b = ((float)bl*minusf+(float)br*f)/255.0f;
    return t*minusg+b*g;
}

__global__ void
enlarge(unsigned char *image, float *enlarged)
{

    int src_width = cudaParam.src_width;
    int src_height = cudaParam.src_height;
    int dst_width = cudaParam.dst_width;
    int dst_height = cudaParam.dst_height;

    int pixelX = blockIdx.x*blockDim.x+threadIdx.x-PADDING;
    int pixelY = blockIdx.y*blockDim.y+threadIdx.y-PADDING;
    int buffId = (blockIdx.y*blockDim.y+threadIdx.y) * cudaParam.dst_width_padded +
                    (blockIdx.x*blockDim.x+threadIdx.x);
    // printf("threadId: %d\n", threadId);
    // printf("pixelX: %d, pixelY: %d\n", pixelX, pixelY);
    if (pixelX<dst_width+PADDING && pixelY<dst_height+PADDING) {
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
        
        enlarged[3*buffId] = interpolate(image[tl],image[tr],image[bl],image[br],f,g);
        enlarged[3*buffId+1] = interpolate(image[tl+1],image[tr+1],image[bl+1],image[br+1],f,g);
        enlarged[3*buffId+2] = interpolate(image[tl+2],image[tr+2],image[bl+2],image[br+2],f,g);
    }
}


__global__ void
compute_luminance(float *image, float *luminace) 
{
    int pixelX = blockIdx.x*blockDim.x+threadIdx.x;
    int pixelY = blockIdx.y*blockDim.y+threadIdx.y;
    int buffId = pixelY * cudaParam.dst_width_padded + pixelX;
    if (pixelX<cudaParam.dst_width_padded && pixelY<cudaParam.dst_height_padded) {
        luminace[buffId] = (image[3*buffId]*2+image[3*buffId+1]*3 
            + image[3*buffId]) / 6.0f;
    }
}

__device__ __inline__ float 
min3v(float a, float b, float c) {
    return min(a,min(b,c));
}

__device__ __inline__ float 
max3v(float a, float b, float c) {
    return max(a,max(b,c));
}

__device__ __inline__ void 
get_largest(float strength, float *image, float *lum,
    float color[4], int cc, int a, int b, int c)
{
    float minusStrength = 1 - strength;
    float new_lum = lum[cc] * minusStrength +
        ((lum[a] + lum[b] + lum[c]) / 3) * strength;
    
    if (new_lum > color[3]) {
        color[0] = image[cc * 3] * minusStrength +
            ((image[a * 3] + image[b * 3] + image[c * 3]) / 3) * strength;
        color[1] = image[cc * 3 + 1] * minusStrength +
            ((image[a * 3 + 1] + image[b * 3 + 1] + image[c * 3 + 1]) / 3) * strength;
        color[2] = image[cc * 3 + 2] * minusStrength +
            ((image[a * 3 + 2] + image[b * 3 + 2] + image[c * 3 + 2]) / 3) * strength;
        color[3] = new_lum;
    }
}



__global__ void
preprocess(float *image, float *lum, float *preprocessed)
{
    int dst_width = cudaParam.dst_width;
    int dst_height = cudaParam.dst_height;

    int pixelX = blockIdx.x*blockDim.x+threadIdx.x-PADDING;
    int pixelY = blockIdx.y*blockDim.y+threadIdx.y-PADDING;
    int buffId = (blockIdx.y*blockDim.y+threadIdx.y) * cudaParam.dst_width_padded +
                    (blockIdx.x*blockDim.x+threadIdx.x);
    float color[4];

    if (pixelX >= -PADDING+1 && pixelY >= -PADDING+1 &&
        pixelX < dst_width+PADDING-1 && pixelY < dst_height+PADDING-1) {
        color[0] = image[3 * buffId];
        color[1] = image[3 * buffId + 1];
        color[2] = image[3 * buffId + 2];
        color[3] = lum[buffId];
        
        int cc_ix = buffId;
        int r_ix = cc_ix + 1;
        int l_ix = cc_ix - 1;
        int t_ix = cc_ix - cudaParam.dst_width_padded;
        int tl_ix = t_ix - 1;
        int tr_ix = t_ix + 1;
        int b_ix = cc_ix + cudaParam.dst_width_padded;
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

        float max0 = max3v(br, b, bl);
        float min0 = min3v(tl, t, tr);
        float max1 = max3v(tl, t, tr);
        float min1 = min3v(br, b, bl);
        float max2 = max3v(cc, l, b);
        float min2 = min3v(r, t, tr);
        float max3 = max3v(cc, r, t);
        float min3 = min3v(bl, l, b);
        float max4 = max3v(l, tl, bl);
        float min4 = min3v(r, br, tr);
        float max5 = max3v(r, br, tr);
        float min5 = min3v(l, tl, bl);
        float max6 = max3v(cc, l, t);
        float min6 = min3v(r, br, b);
        float max7 = max3v(cc, r, b);
        float min7 = min3v(t, l, tl);


        if (min0 > cc && min0 > max1) {
            get_largest(strength, image, lum, color,
                cc_ix, tl_ix, t_ix, tr_ix);
        } else if (min1 > cc && min1 > max1) {
            get_largest(strength, image, lum, color,
                cc_ix, br_ix, b_ix, bl_ix);
        }

        if (min2 > max2) {
            get_largest(strength, image, lum, color,
                cc_ix, r_ix, t_ix, tr_ix);
        } else if (min3 > max3) {
            get_largest(strength, image, lum, color,
                cc_ix, bl_ix, l_ix, b_ix);
        }

        if (min4 > cc && min4 > max4) {
            get_largest(strength, image, lum, color,
                cc_ix, r_ix, br_ix, tr_ix);
        } else if (min5 > cc && min5 > max5) {
            get_largest(strength, image, lum, color,
                cc_ix, l_ix, tl_ix, bl_ix);
        }

        if (min6 > max6) {
            get_largest(strength, image, lum, color,
                cc_ix, r_ix, br_ix, b_ix);
        } else if (min7 > max7) {
            get_largest(strength, image, lum, color,
                cc_ix, t_ix, l_ix, tl_ix);
        }


        preprocessed[3 * buffId] = color[0];
        preprocessed[3 * buffId + 1] = color[1];
        preprocessed[3 * buffId + 2] = color[2];
    }
}


__device__ __inline__ float 
clamp(float x, float lower, float upper)
{
    return min(upper,max(x,lower));
}

__global__ void
compute_graident(float *lum, float *gradient)
{
    int dst_width = cudaParam.dst_width;
    int dst_height = cudaParam.dst_height;

    int pixelX = blockIdx.x*blockDim.x+threadIdx.x-PADDING;
    int pixelY = blockIdx.y*blockDim.y+threadIdx.y-PADDING;
    int buffId = (blockIdx.y*blockDim.y+threadIdx.y) * cudaParam.dst_width_padded +
                    (blockIdx.x*blockDim.x+threadIdx.x);

    if (pixelX >= -PADDING+1 && pixelY >= -PADDING+1 &&
        pixelX < dst_width+PADDING-1 && pixelY < dst_height+PADDING-1) {
        int cc_ix = buffId;
    
        /* [tl t tr]
         * [l cc  r]
         * [bl b br]
         */
        int t_ix = cc_ix - cudaParam.dst_width_padded;
        int tl_ix = t_ix - 1;
        int tr_ix = t_ix + 1;
        int l_ix = cc_ix - 1;
        int r_ix = cc_ix + 1;
        int b_ix = cc_ix + cudaParam.dst_width_padded;
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
            1.0f - clamp(sqrt(xgrad * xgrad + ygrad * ygrad), 0.0f, 1.0f);
    }
}


__device__ __inline__ void 
get_average(float strength, float *image, float color[3],
    int cc, int a, int b, int c)
{   
    color[0] = image[cc * 3] * (1.0f - strength) +
        ((image[a * 3] + image[b * 3] + image[c * 3]) / 3.0f) * strength;
    color[1] = image[cc * 3 + 1] * (1.0f - strength) +
        ((image[a * 3 + 1] + image[b * 3 + 1] + image[c * 3 + 1]) / 3.0f) * strength;
    color[2] = image[cc * 3 + 2] * (1.0f - strength) +
        ((image[a * 3 + 2] + image[b * 3 + 2] + image[c * 3 + 2]) / 3.0f) * strength;
}


__global__ void
push(float *image, float *gradient, float *pushed)
{

    float color[3];
    int dst_width = cudaParam.dst_width;
    int dst_height = cudaParam.dst_height;

    int pixelX = blockIdx.x*blockDim.x+threadIdx.x-PADDING;
    int pixelY = blockIdx.y*blockDim.y+threadIdx.y-PADDING;
    int buffId = (blockIdx.y*blockDim.y+threadIdx.y) * cudaParam.dst_width_padded +
                    (blockIdx.x*blockDim.x+threadIdx.x);

    if (pixelX >= -PADDING+1 && pixelY >= -PADDING+1 &&
        pixelX < dst_width+PADDING-1 && pixelY < dst_height+PADDING-1) {
        color[0] = image[3 * buffId];
        color[1] = image[3 * buffId + 1];
        color[2] = image[3 * buffId + 2];

        int cc_ix = buffId;
        int r_ix = cc_ix + 1;
        int l_ix = cc_ix - 1;
        int t_ix = cc_ix - cudaParam.dst_width_padded;
        int tl_ix = t_ix - 1;
        int tr_ix = t_ix + 1;
        int b_ix = cc_ix + cudaParam.dst_width_padded;
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

        float max0 = max3v(br, b, bl);
        float min0 = min3v(tl, t, tr);
        float max1 = max3v(tl, t, tr);
        float min1 = min3v(br, b, bl);
        float max2 = max3v(cc, l, b);
        float min2 = min3v(r, t, tr);
        float max3 = max3v(cc, r, t);
        float min3 = min3v(bl, l, b);
        float max4 = max3v(l, tl, bl);
        float min4 = min3v(r, br, tr);
        float max5 = max3v(r, br, tr);
        float min5 = min3v(l, tl, bl);
        float max6 = max3v(cc, l, t);
        float min6 = min3v(r, br, b);
        float max7 = max3v(cc, r, b);
        float min7 = min3v(t, l, tl);

        if ( min0 > cc && min0 > max0) {
            get_average(strength, image, color,
                cc_ix, tl_ix, t_ix, tr_ix);
        } else if (min1 > cc &&  min1 > max1) {
            get_average(strength, image, color,
                cc_ix, br_ix, b_ix, bl_ix);
        } else if (min2 > max2) {
            get_average(strength, image, color,
                cc_ix, r_ix, t_ix, tr_ix);
        } else if (min3 > max3) {
            get_average(strength, image, color,
                cc_ix, bl_ix, l_ix, b_ix);
        } else if (min4 > cc && min4 > max4) {
            get_average(strength, image, color,
                cc_ix, r_ix, br_ix, tr_ix);
        } else if (min5 > cc && min5 > max5) {
            get_average(strength, image, color,
                cc_ix, l_ix, tl_ix, bl_ix);    
        } else if (min6 > max6) {
            get_average(strength, image, color,
                cc_ix, r_ix, br_ix, b_ix);
        } else if (min7 > max7) {
            get_average(strength, image, color,
                cc_ix, t_ix, l_ix, tl_ix);
        }

        pushed[3 * buffId] = color[0];
        pushed[3 * buffId + 1] = color[1];
        pushed[3 * buffId + 2] = color[2];
    }
}

__device__ __inline__ unsigned char
quantize(float x) 
{
    int r = x * 255;
    return min(255,max(r,0));
}

__global__ void
output(float *image, unsigned char *dst)
{
    int dst_width = cudaParam.dst_width;
    int dst_height = cudaParam.dst_height;

    int pixelX = blockIdx.x*blockDim.x+threadIdx.x-PADDING;
    int pixelY = blockIdx.y*blockDim.y+threadIdx.y-PADDING;
    int pixelId = pixelY*dst_width+pixelX;
    int buffId = (blockIdx.y*blockDim.y+threadIdx.y) * cudaParam.dst_width_padded +
                    (blockIdx.x*blockDim.x+threadIdx.x);
    if (pixelX >= 0 && pixelY >= 0 &&
        pixelX < dst_width && pixelY < dst_height) {
        dst[4*pixelId] = quantize(image[3*buffId]);
        dst[4*pixelId+1] = quantize(image[3*buffId+1]);
        dst[4*pixelId+2] = quantize(image[3*buffId+2]);
        dst[4*pixelId+3] = 255;
    
        // dst[4*pixelId] = quantize(image[buffId]);
        // dst[4*pixelId+1] = quantize(image[buffId]);
        // dst[4*pixelId+2] = quantize(image[buffId]);
        // dst[4*pixelId+3] = 255;
    }
}




void Anime4kCuda::run()
{
    dim3 gridDim((param.dst_width_padded+THREADW-1)/THREADW, 
                (param.dst_height_padded+THREADH-1)/THREADH);
    dim3 blockDim(THREADW,THREADH);

    START_ACTIVITY(ACTIVITY_COPY);
    cudaMemcpy(cudaImage, image_, param.src_bytes,cudaMemcpyHostToDevice);
    FINISH_ACTIVITY(ACTIVITY_COPY);

    START_ACTIVITY(ACTIVITY_LINEAR);
    enlarge<<<gridDim,blockDim>>>(cudaImage,imageBuff);
    cudaDeviceSynchronize();
    START_ACTIVITY(ACTIVITY_LINEAR);

    START_ACTIVITY(ACTIVITY_LUM);
    compute_luminance<<<gridDim,blockDim>>>(imageBuff, luminaceBuff);
    cudaDeviceSynchronize();
    FINISH_ACTIVITY(ACTIVITY_LUM);

    START_ACTIVITY(ACTIVITY_THINLINES);
    preprocess<<<gridDim,blockDim>>>(imageBuff,luminaceBuff,preprocessedBuff);
    cudaDeviceSynchronize();    
    FINISH_ACTIVITY(ACTIVITY_THINLINES);


    START_ACTIVITY(ACTIVITY_LUM);
    compute_luminance<<<gridDim,blockDim>>>(preprocessedBuff, luminaceBuff);
    cudaDeviceSynchronize();
    FINISH_ACTIVITY(ACTIVITY_LUM);


    START_ACTIVITY(ACTIVITY_GRADIENT);
    compute_graident<<<gridDim,blockDim>>>(luminaceBuff, gradientBuff);
    cudaDeviceSynchronize();
    FINISH_ACTIVITY(ACTIVITY_GRADIENT);

    START_ACTIVITY(ACTIVITY_REFINE);
    push<<<gridDim,blockDim>>>(preprocessedBuff, gradientBuff, imageBuff);
    cudaDeviceSynchronize();
    FINISH_ACTIVITY(ACTIVITY_REFINE);


    START_ACTIVITY(ACTIVITY_COPY);
    output<<<gridDim,blockDim>>>(imageBuff, cudaResult);
    cudaDeviceSynchronize();
    cudaMemcpy(result_, cudaResult, param.dst_bytes,cudaMemcpyDeviceToHost);
    FINISH_ACTIVITY(ACTIVITY_COPY);

}