#ifndef ANIME4K_OMP_H_
#define ANIME4K_OMP_H_

#include "anime4k.h"

class Anime4kOmp : public Anime4k {
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
    unsigned char *result_;
    float strength_thinlines_;
    float strength_refine_;
public:
    Anime4kOmp(
        unsigned int width, unsigned int height, unsigned char *image,
        unsigned int new_width, unsigned int new_height);
    virtual ~Anime4kOmp();
    void run();
    unsigned char *get_image() { return result_; }
};

#endif /* ANIME4K_OMP_H_ */
