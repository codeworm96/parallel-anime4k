#ifndef ANIME4K_SEQ_H_
#define ANIME4K_SEQ_H_

#include "anime4k.h"

class Anime4kSeq : public Anime4k {
private:
    unsigned int old_width_;
    unsigned int old_height_;
    unsigned char *image_;
    unsigned int width_;
    unsigned int height_;
    double *original_;
    double *enlarge_;
    double *lum_;
    double *preprocessing_;
    double *gradients_;
    double *final_;
    unsigned char *result_;
    double strength_preprocessing_;
    double strength_push_;
public:
    Anime4kSeq(
        unsigned int width, unsigned int height, unsigned char *image,
        unsigned int new_width, unsigned int new_height);
    virtual ~Anime4kSeq();
    void run();
    unsigned char *get_image() { return result_; }
};

#endif /* ANIME4K_SEQ_H_ */
