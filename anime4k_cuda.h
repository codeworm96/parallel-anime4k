#ifndef ANIME4K_CUDA_H_
#define ANIME4K_CUDA_H_

#include "anime4k.h"

struct Param {
    unsigned int src_width;
    unsigned int src_height;
    unsigned int dst_width;
    unsigned int dst_height;
    unsigned int src_bytes;
    unsigned int dst_bytes;
    float strength_preprocessing;
    float strength_push;
};

class Anime4kCuda : public Anime4k {
private:
    Param param;
    unsigned char *image_;
    unsigned char *result_;

public:
    Anime4kCuda(
        unsigned int width, unsigned int height, unsigned char *image,
        unsigned int new_width, unsigned int new_height);
    virtual ~Anime4kCuda();
    void run();
    unsigned char *get_image() { return result_; }
};

#endif /* ANIME4K_SEQ_H_ */
