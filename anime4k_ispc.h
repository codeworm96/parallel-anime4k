#ifndef ANIME4K_ISPC_H_
#define ANIME4K_ISPC_H_

#include "anime4k.h"

class Anime4kIspc : public Anime4k {
private:
    unsigned int old_width_;
    unsigned int old_height_;
    unsigned char *image_;
    unsigned int width_;
    unsigned int height_;
    float *original_;
    float *enlarge_;
    float *lum_;
    float *thinlines_;
    float *gradients_;
    float *refined_;
    unsigned char *result_;
    float strength_thinlines_;
    float strength_refine_;
public:
    Anime4kIspc(
        unsigned int width, unsigned int height, unsigned char *image,
        unsigned int new_width, unsigned int new_height);
    virtual ~Anime4kIspc();
    void run();
    unsigned char *get_image() { return result_; }
};

#endif /* ANIME4K_ISPC_H_ */
