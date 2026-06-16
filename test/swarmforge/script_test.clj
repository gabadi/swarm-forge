(ns swarmforge.script-test
  (:require [babashka.fs :as fs]
            [clojure.java.shell :as sh]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]))

(def repo-root (fs/cwd))
(def scripts-dir (fs/path repo-root "swarmforge" "scripts"))

(defn write-file [path text]
  (fs/create-dirs (fs/parent path))
  (spit (str path) text))

(defn run
  [{:keys [dir env ok?]} & args]
  (let [result (apply sh/sh (concat args [:dir (str dir)
                                          :env (merge {"PATH" (System/getenv "PATH")
                                                       "GIT_CONFIG_NOSYSTEM" "1"}
                                                      env)]))]
    (when (and (not (false? ok?)) (not= 0 (:exit result)))
      (throw (ex-info (str "Command failed: " (str/join " " args))
                      (assoc result :args args))))
    result))

(defn init-repo! [root]
  (run {:dir root} "git" "init" "-q")
  (run {:dir root} "git" "config" "user.email" "test@example.com")
  (run {:dir root} "git" "config" "user.name" "Test User")
  (write-file (fs/path root "README.md") "initial\n")
  (run {:dir root} "git" "add" "README.md")
  (run {:dir root} "git" "commit" "-q" "-m" "Initial commit"))

(defn tmp-dir []
  (fs/create-temp-dir {:prefix "swarmforge-script-test."}))

(defn zsh
  ([root source]
   (zsh root source true))
  ([root source ok?]
   (run {:dir root
         :env {"SCRIPTS_DIR" (str scripts-dir)}
         :ok? ok?}
        "zsh" "-c" source)))

(deftest handoff-lib-parses-and-prints-handoff-files
  (let [root (tmp-dir)
        handoff-file (fs/path root "task.handoff")]
    (try
      (write-file handoff-file
                  (str "id: 1\n"
                       "from: coder\n"
                       "to: cleaner\n"
                       "priority: 10\n"
                       "type: git_handoff\n"
                       "task: task-alpha\n"
                       "\n"
                       "merge_and_process coder abcdef1234\n"))
      (let [result (zsh root
                        (str "source \"$SCRIPTS_DIR/handoff-lib.sh\"\n"
                             "handoff_header_field task task.handoff\n"
                             "handoff_body task.handoff\n"
                             "handoff_print_task task.handoff\n"))]
        (is (str/includes? (:out result) "task-alpha"))
        (is (str/includes? (:out result) "merge_and_process coder abcdef1234"))
        (is (str/includes? (:out result) "TASK: task.handoff"))
        (is (str/includes? (:out result) "FROM: coder"))
        (is (str/includes? (:out result) "TASK_NAME: task-alpha")))
      (finally
        (fs/delete-tree root)))))

(deftest handoff-lib-updates-headers-and-reads-role-state
  (let [root (tmp-dir)]
    (try
      (init-repo! root)
      (write-file (fs/path root ".swarmforge/roles.tsv")
                  (str "coder\tmaster\t" root "\tsession\tCoder\tcodex\ttask\n"
                       "cleaner\tcleaner\t" root "/.worktrees/cleaner\tsession\tCleaner\tcodex\tbatch\n"))
      (write-file (fs/path root ".swarmforge/handoffs/inbox/new/item.handoff")
                  (str "id: 1\n"
                       "from: coder\n"
                       "to: cleaner\n"
                       "priority: 20\n"
                       "type: note\n"
                       "\n"
                       "payload\n"))
      (let [result (zsh root
                        (str "source \"$SCRIPTS_DIR/handoff-lib.sh\"\n"
                             "handoff_role_known cleaner\n"
                             "handoff_role_receive_mode cleaner\n"
                             "handoff_role_worktree_name cleaner\n"
                             "handoff_set_header .swarmforge/handoffs/inbox/new/item.handoff dequeued_at 2026-06-16T00:00:00Z\n"
                             "handoff_header_field dequeued_at .swarmforge/handoffs/inbox/new/item.handoff\n"
                             "handoff_next_sequence\n"
                             "printf '\\n'\n"
                             "handoff_next_sequence\n"))]
        (is (str/includes? (:out result) "batch"))
        (is (str/includes? (:out result) "cleaner"))
        (is (str/includes? (:out result) "2026-06-16T00:00:00Z"))
        (is (str/includes? (:out result) "000001"))
        (is (str/includes? (:out result) "000002")))
      (finally
        (fs/delete-tree root)))))

(deftest swarmforge-launcher-parses-config-and-writes-state-files
  (let [root (tmp-dir)]
    (try
      (write-file (fs/path root "swarmforge/constitution.prompt")
                  "Read articles.\n")
      (write-file (fs/path root "swarmforge/swarmforge.conf")
                  (str "# comment\n"
                       "window coder codex master\n"
                       "window cleaner codex cleaner batch\n"))
      (write-file (fs/path root "swarmforge/roles/coder.prompt") "coder\n")
      (write-file (fs/path root "swarmforge/roles/cleaner.prompt") "cleaner\n")
      (let [result (zsh root
                        (str "SWARMFORGE_SOURCE_ONLY=1 source \"$SCRIPTS_DIR/swarmforge.sh\" \"$PWD\"\n"
                             "parse_config\n"
                             "prepare_workspace\n"
                             "printf '%s\\n' \"${ROLES[1]} ${DISPLAY_NAMES[1]} ${WORKTREE_PATHS[1]} ${RECEIVE_MODES[1]}\"\n"
                             "printf '%s\\n' \"${ROLES[2]} ${DISPLAY_NAMES[2]} ${WORKTREE_PATHS[2]} ${RECEIVE_MODES[2]}\"\n"
                             "cat .swarmforge/roles.tsv\n"
                             "cat .swarmforge/sessions.tsv\n"))]
        (is (str/includes? (:out result) "coder Coder"))
        (is (str/includes? (:out result) "cleaner Cleaner"))
        (is (str/includes? (:out result) "cleaner batch"))
        (is (str/includes? (:out result) "swarmforge-coder"))
        (is (str/includes? (:out result) "swarmforge-cleaner"))
        (is (fs/exists? (fs/path root ".swarmforge/tmux-socket"))))
      (finally
        (fs/delete-tree root)))))

(deftest swarmforge-launcher-rejects-invalid-config
  (let [root (tmp-dir)]
    (try
      (write-file (fs/path root "swarmforge/constitution.prompt")
                  "Read articles.\n")
      (write-file (fs/path root "swarmforge/swarmforge.conf")
                  (str "window coder codex master\n"
                       "window coder codex other\n"))
      (write-file (fs/path root "swarmforge/roles/coder.prompt") "coder\n")
      (let [result (zsh root
                        (str "SWARMFORGE_SOURCE_ONLY=1 source \"$SCRIPTS_DIR/swarmforge.sh\" \"$PWD\"\n"
                             "parse_config\n")
                        false)]
        (is (= 1 (:exit result)))
        (is (str/includes? (:out result) "Duplicate role 'coder'")))
      (finally
        (fs/delete-tree root)))))

(deftest window-watchdog-rewrites-window-state-and-id-list
  (let [root (tmp-dir)
        state-file (fs/path root "windows.tsv")
        ids-file (fs/path root "window-ids")]
    (try
      (write-file state-file
                  (str "1\told-a\tswarmforge-coder\tSwarmForge Coder\n"
                       "2\told-b\tswarmforge-cleaner\tSwarmForge Cleaner\n"))
      (write-file ids-file "old-a\nold-b\n")
      (let [result (zsh root
                        (str "SWARMFORGE_SOURCE_ONLY=1 source \"$SCRIPTS_DIR/swarm-window-watchdog.sh\" "
                             "windows.tsv window-ids 1 /tmp/nonexistent.sock \"$PWD\" none\n"
                             "rewrite_window_id 2 new-b\n"
                             "cat windows.tsv\n"
                             "printf -- '---\\n'\n"
                             "cat window-ids\n"))]
        (is (str/includes? (:out result) "1\told-a\tswarmforge-coder\tSwarmForge Coder"))
        (is (str/includes? (:out result) "2\tnew-b\tswarmforge-cleaner\tSwarmForge Cleaner"))
        (is (str/includes? (:out result) "old-a\nnew-b\n")))
      (finally
        (fs/delete-tree root)))))

(deftest swarm-cleanup-tolerates-missing-runtime-state
  (let [root (tmp-dir)
        ids-file (fs/path root ".swarmforge/window-ids")]
    (try
      (write-file ids-file "window-a\nwindow-b\n")
      (let [result (run {:dir root
                         :env {"SWARMFORGE_TERMINAL_BACKEND" "none"}}
                        (str (fs/path scripts-dir "swarm-cleanup.sh"))
                        "/tmp/nonexistent.sock"
                        (str ids-file))]
        (is (= 0 (:exit result)))
        (is (= "" (:err result))))
      (finally
        (fs/delete-tree root)))))
