#ifndef ANIME4K_H_
#define ANIME4K_H_

class Anime4k {
public:
    virtual ~Anime4k() {}
    virtual void run() = 0;
    virtual unsigned char *get_image() = 0;
};

#endif /* ANIME4K_H_ */
