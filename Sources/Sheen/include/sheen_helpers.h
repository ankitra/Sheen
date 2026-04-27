#ifndef sheen_helpers_h
#define sheen_helpers_h

/// Non-variadic wrapper around git_commit_create.
/// Uses void* to avoid depending on git2.h in the header.
int cgit_commit_create(
    void *out, void *repo,
    const char *update_ref,
    const void *author, const void *committer,
    const char *message_encoding, const char *message,
    void *tree, int parent_count,
    void *parent1, void *parent2);

#endif
