#include "sheen_helpers.h"
#include <git2.h>

int cgit_commit_create(
    void *out, void *repo,
    const char *update_ref,
    const void *author, const void *committer,
    const char *message_encoding, const char *message,
    void *tree, int parent_count,
    void *parent1, void *parent2) {

    git_oid *oid_out = (git_oid *)out;
    git_repository *r = (git_repository *)repo;
    const git_signature *a = (const git_signature *)author;
    const git_signature *c = (const git_signature *)committer;
    const git_tree *t = (const git_tree *)tree;
    const git_commit *p1 = (const git_commit *)parent1;
    const git_commit *p2 = (const git_commit *)parent2;

    const git_commit *parents[] = { p1, p2 };
    return git_commit_create(oid_out, r, update_ref, a, c,
                            message_encoding, message, t,
                            parent_count, parents);
}
