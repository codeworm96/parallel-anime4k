#ifndef ANIME4K_SEQ_H_
#define ANIME4K_SEQ_H_

typedef struct anime4k_seq_ctx anime4k_seq_ctx_t;

anime4k_seq_ctx_t *anime4k_seq_init(
    unsigned int width, unsigned int height, unsigned char *image,
    unsigned int new_width, unsigned int new_height);

void anime4k_seq_run(anime4k_seq_ctx_t *ctx);

unsigned char *anime4k_seq_get_image(anime4k_seq_ctx_t *ctx);

void anime4k_seq_free(anime4k_seq_ctx_t *ctx);

#endif /* ANIME4K_SEQ_H_ */
