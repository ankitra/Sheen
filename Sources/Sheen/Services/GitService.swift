import Foundation
import CGit

// MARK: - Errors

enum GitError: LocalizedError {
    case notInitialized
    case cloneFailed(String)
    case openFailed(String)
    case statusFailed(String)
    case stagingFailed(String)
    case commitFailed(String)
    case pushFailed(String)
    case pullFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:      return "Repository not initialized"
        case .cloneFailed(let m):  return "Clone failed: \(m)"
        case .openFailed(let m):   return "Open failed: \(m)"
        case .statusFailed(let m): return "Status check failed: \(m)"
        case .stagingFailed(let m):return "Staging failed: \(m)"
        case .commitFailed(let m): return "Commit failed: \(m)"
        case .pushFailed(let m):   return "Push failed: \(m)"
        case .pullFailed(let m):   return "Pull failed: \(m)"
        }
    }
}

// MARK: - GitService

final class GitService {
    private var repo: OpaquePointer?

    var isInitialized: Bool { repo != nil }

    deinit {
        if let repo { git_repository_free(repo) }
    }

    // MARK: - Setup

    func cloneRepository(from url: String, credentialsToken: String, to destination: URL) async throws {
        var opts = git_clone_options()
        git_clone_options_init(&opts, UInt32(GIT_CLONE_OPTIONS_VERSION))
        opts.fetch_opts = makeFetchOptions(credentialsToken: credentialsToken)

        var out: OpaquePointer?
        let result = git_clone(&out, url, destination.path, &opts)
        guard result == 0, let out else {
            throw GitError.cloneFailed("\(result)")
        }
        repo = out
    }

    func openRepository(at url: URL) async throws {
        var out: OpaquePointer?
        let result = git_repository_open(&out, url.path)
        guard result == 0, let out else {
            throw GitError.openFailed("\(result)")
        }
        repo = out
    }

    // MARK: - Status

    func hasChanges() async throws -> Bool {
        guard let repo else { throw GitError.notInitialized }

        var opts = git_status_options()
        git_status_options_init(&opts, UInt32(GIT_STATUS_OPTIONS_VERSION))
        opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
        opts.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue

        var list: OpaquePointer?
        let result = git_status_list_new(&list, repo, &opts)
        guard result == 0 else { throw GitError.statusFailed("\(result)") }
        defer { git_status_list_free(list) }

        return git_status_list_entrycount(list) > 0
    }

    // MARK: - Stage & Commit

    func stageAll() async throws {
        guard let repo else { throw GitError.notInitialized }

        var index: OpaquePointer?
        let idxResult = git_repository_index(&index, repo)
        guard idxResult == 0 else { throw GitError.stagingFailed("\(idxResult)") }
        defer { git_index_free(index) }

        var pathspec = git_strarray()
        let addResult = git_index_add_all(index, &pathspec, 0, nil, nil)
        guard addResult == 0 else { throw GitError.stagingFailed("add-all \(addResult)") }

        let writeResult = git_index_write(index)
        guard writeResult == 0 else { throw GitError.stagingFailed("write \(writeResult)") }
    }

    func commit(message: String) async throws {
        guard let repo else { throw GitError.notInitialized }

        // 1. Get index
        var index: OpaquePointer?
        let idxResult = git_repository_index(&index, repo)
        guard idxResult == 0 else { throw GitError.commitFailed("index \(idxResult)") }
        defer { git_index_free(index) }

        // 2. Write tree from index
        var treeOID = git_oid()
        let treeResult = git_index_write_tree(&treeOID, index)
        guard treeResult == 0 else { throw GitError.commitFailed("write-tree \(treeResult)") }

        // 3. Look up tree object
        var tree: OpaquePointer?
        let lookupResult = git_tree_lookup(&tree, repo, &treeOID)
        guard lookupResult == 0 else { throw GitError.commitFailed("tree-lookup \(lookupResult)") }
        defer { git_tree_free(tree) }

        // 4. Get parent commit from HEAD (if one exists)
        var parent1Commit: OpaquePointer?
        var parentCount: Int32 = 0

        var headRef: OpaquePointer?
        if git_repository_head(&headRef, repo) == 0 {
            defer { git_reference_free(headRef) }

            var parentObj: OpaquePointer?
            if git_reference_peel(&parentObj, headRef, GIT_OBJECT_COMMIT) == 0,
               let obj = parentObj,
               let oid = git_object_id(obj) {
                var commit: OpaquePointer?
                if git_commit_lookup(&commit, repo, oid) == 0 {
                    parent1Commit = commit
                    parentCount = 1
                }
            }
        }
        defer { if let p = parent1Commit { git_commit_free(p) } }

        // 5. Create signature (allocated by libgit2, must free)
        var sigPtr: UnsafeMutablePointer<git_signature>?
        let sigResult = git_signature_now(&sigPtr, "Sheen", "sheen@local")
        guard sigResult == 0, let sig = sigPtr else {
            throw GitError.commitFailed("signature")
        }
        defer { git_signature_free(sig) }

        // 6. Create commit using non-variadic C helper
        var commitOID = git_oid()
        let commitResult = cgit_commit_create(
            &commitOID,
            UnsafeMutableRawPointer(repo),
            "HEAD",
            sig, sig,
            nil, message,
            UnsafeMutableRawPointer(tree),
            parentCount,
            parent1Commit.map { UnsafeMutableRawPointer($0) }, nil
        )
        guard commitResult == 0 else {
            throw GitError.commitFailed("create \(commitResult)")
        }
    }

    // MARK: - Push

    func push(credentialsToken: String) async throws {
        guard let repo else { throw GitError.notInitialized }

        var remote: OpaquePointer?
        let lookupResult = git_remote_lookup(&remote, repo, "origin")
        guard lookupResult == 0 else { throw GitError.pushFailed("remote-lookup \(lookupResult)") }
        defer { git_remote_free(remote) }

        var callbacks = makeRemoteCallbacks(credentialsToken: credentialsToken)

        let connectResult = git_remote_connect(remote, GIT_DIRECTION_PUSH, &callbacks, nil, nil)
        guard connectResult == 0 else { throw GitError.pushFailed("connect \(connectResult)") }

        let branch = currentBranch()
        let pushRefspec = "refs/heads/\(branch):refs/heads/\(branch)"

        let refspecDup = strdup(pushRefspec)
        defer { free(refspecDup) }
        var refspecPtr: UnsafeMutablePointer<Int8>? = refspecDup
        var refspecs = git_strarray(strings: &refspecPtr, count: 1)

        var pushOpts = git_push_options()
        git_push_options_init(&pushOpts, UInt32(GIT_PUSH_OPTIONS_VERSION))
        pushOpts.callbacks = callbacks

        let pushResult = git_remote_push(remote, &refspecs, &pushOpts)
        guard pushResult == 0 else { throw GitError.pushFailed("push \(pushResult)") }
    }

    // MARK: - Pull

    func pull(credentialsToken: String) async throws {
        guard let repo else { throw GitError.notInitialized }

        var remote: OpaquePointer?
        let lookupResult = git_remote_lookup(&remote, repo, "origin")
        guard lookupResult == 0 else { throw GitError.pullFailed("remote-lookup \(lookupResult)") }
        defer { git_remote_free(remote) }

        var callbacks = makeRemoteCallbacks(credentialsToken: credentialsToken)
        var fetchOpts = makeFetchOptions(credentialsToken: credentialsToken)

        let connectResult = git_remote_connect(remote, GIT_DIRECTION_FETCH, &callbacks, nil, nil)
        guard connectResult == 0 else { throw GitError.pullFailed("connect \(connectResult)") }

        let fetchResult = git_remote_fetch(remote, nil, &fetchOpts, nil)
        guard fetchResult == 0 else { throw GitError.pullFailed("fetch \(fetchResult)") }

        // Fast-forward merge: update local branch to match remote tracking branch
        let branch = currentBranch()
        let remoteRefName = "refs/remotes/origin/\(branch)"

        var remoteRef: OpaquePointer?
        guard git_reference_lookup(&remoteRef, repo, remoteRefName) == 0 else { return }
        defer { git_reference_free(remoteRef) }

        guard let remoteOID = git_reference_target(remoteRef) else { return }
        var remoteOIDCopy = remoteOID.pointee

        var annotatedCommit: OpaquePointer?
        let annotateResult = git_annotated_commit_lookup(&annotatedCommit, repo, &remoteOIDCopy)
        guard annotateResult == 0 else { return }
        defer { git_annotated_commit_free(annotatedCommit) }

        // Merge analysis
        var mergeAnalysis = GIT_MERGE_ANALYSIS_NONE
        var mergePreference = GIT_MERGE_PREFERENCE_NONE
        var theirHeads: [OpaquePointer?] = [annotatedCommit]

        let analysisResult = theirHeads.withUnsafeMutableBufferPointer { buf in
            git_merge_analysis(&mergeAnalysis, &mergePreference, repo, buf.baseAddress, 1)
        }
        guard analysisResult == 0 else { return }

        if (mergeAnalysis.rawValue & UInt32(GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue)) != 0 { return }

        if (mergeAnalysis.rawValue & UInt32(GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue)) != 0 {
            // Fast-forward: update the local branch ref to the remote OID
            let localRefName = "refs/heads/\(branch)"
            var localRef: OpaquePointer?
            guard git_reference_lookup(&localRef, repo, localRefName) == 0 else {
                throw GitError.pullFailed("ff lookup \(localRefName)")
            }
            defer { git_reference_free(localRef) }

            var newLocalRef: OpaquePointer?
            let setRefResult = git_reference_set_target(&newLocalRef, localRef, &remoteOIDCopy, nil)
            guard setRefResult == 0 else { throw GitError.pullFailed("ff \(setRefResult)") }
            defer { git_reference_free(newLocalRef) }

            var checkoutOpts = git_checkout_options()
            git_checkout_options_init(&checkoutOpts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
            checkoutOpts.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
            _ = git_checkout_head(repo, &checkoutOpts)
            return
        }

        // Normal merge
        var mergeOpts = git_merge_options()
        git_merge_options_init(&mergeOpts, UInt32(GIT_MERGE_OPTIONS_VERSION))
        var checkoutOpts = git_checkout_options()
        git_checkout_options_init(&checkoutOpts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
        checkoutOpts.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)

        let mergeResult = theirHeads.withUnsafeMutableBufferPointer { buf in
            git_merge(repo, buf.baseAddress, 1, &mergeOpts, &checkoutOpts)
        }
        guard mergeResult == 0 else { throw GitError.pullFailed("merge \(mergeResult)") }
    }

    // MARK: - Helpers

    private func currentBranch() -> String {
        guard let repo else { return "main" }
        var head: OpaquePointer?
        guard git_repository_head(&head, repo) == 0 else { return "main" }
        defer { git_reference_free(head) }
        guard let name = git_reference_shorthand(head) else { return "main" }
        return String(cString: name)
    }

    private func makeFetchOptions(credentialsToken: String) -> git_fetch_options {
        var callbacks = makeRemoteCallbacks(credentialsToken: credentialsToken)
        var opts = git_fetch_options()
        git_fetch_options_init(&opts, UInt32(GIT_FETCH_OPTIONS_VERSION))
        opts.callbacks = callbacks
        return opts
    }

    private func makeRemoteCallbacks(credentialsToken: String) -> git_remote_callbacks {
        var callbacks = git_remote_callbacks()
        callbacks.version = UInt32(GIT_REMOTE_CALLBACKS_VERSION)
        pendingToken = credentialsToken
        callbacks.payload = Unmanaged.passUnretained(self).toOpaque()
        callbacks.credentials = { cred, _, _, _, payload in
            guard let payload else { return -1 }
            let service = Unmanaged<GitService>.fromOpaque(payload).takeUnretainedValue()
            guard let token = service.pendingToken else { return -1 }
            return git_cred_userpass_plaintext_new(cred, "token", token)
        }
        return callbacks
    }

    private var pendingToken: String?
}
