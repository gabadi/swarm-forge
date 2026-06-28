#!/usr/bin/env bb
;; Fork extension tests — verify fork.bb overrides exist and produce correct output.
;; Run: bb test/fork_runner.bb

(require '[babashka.fs :as fs]
         '[babashka.process :as process]
         '[clojure.string :as str])

;; Stubs for swarmforge.bb constants used only in install-skills! (not under test here).
(def cyan "") (def green "") (def yellow "") (def reset "")
(defn sq [v] (str "'" v "'"))

(load-file (str (fs/cwd) "/swarmforge/scripts/fork.bb"))

(def failures (atom []))

(defn check [label ok?]
  (if ok?
    (println (str "  ok  " label))
    (do (println (str "  FAIL " label))
        (swap! failures conj label))))

;;; write-agent-instruction-file!

(let [tmp (str (fs/create-temp-file {:prefix "test-instr" :suffix ".md"}))]
  (write-agent-instruction-file! "coder" tmp)
  (let [content (slurp tmp)]
    (check "agent-instruction: contains role identity"
           (str/includes? content "You are the coder in a SwarmForge multi-agent development swarm."))
    (check "agent-instruction: points to swarm-persona skill"
           (str/includes? content "swarm-persona skill"))
    (check "agent-instruction: no Invoke directive (double-load guard)"
           (not (str/includes? content "Invoke"))))
  (fs/delete (fs/path tmp)))

;;; write-worktree-settings!

(let [tmp (str (fs/create-temp-dir {:prefix "test-wt-"}))]
  (write-worktree-settings! "claude" tmp)
  (let [content (slurp (str (fs/path tmp ".claude" "settings.local.json")))]
    (check "worktree-settings[claude]: autoCompactEnabled"          (str/includes? content "autoCompactEnabled"))
    (check "worktree-settings[claude]: CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" (str/includes? content "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"))
    (check "worktree-settings[claude]: CLAUDE_CODE_AUTO_COMPACT_WINDOW" (str/includes? content "CLAUDE_CODE_AUTO_COMPACT_WINDOW"))
    (check "worktree-settings[claude]: UserPromptSubmit hook"       (str/includes? content "UserPromptSubmit"))
    (check "worktree-settings[claude]: Stop hook"                   (str/includes? content "Stop"))
    (check "worktree-settings[claude]: gh pr merge allow rule"      (str/includes? content "gh pr merge"))
    (check "worktree-settings[claude]: git reset allow rule"        (str/includes? content "git reset --hard origin/")))
  (fs/delete-tree (fs/path tmp)))

(let [tmp (str (fs/create-temp-dir {:prefix "test-wt-pi-"}))]
  (write-worktree-settings! "pi" tmp)
  (let [content (slurp (str (fs/path tmp ".pi" "settings.json")))]
    (check "worktree-settings[pi]: .pi/settings.json created"       (fs/exists? (fs/path tmp ".pi" "settings.json")))
    (check "worktree-settings[pi]: no .claude dir"                 (not (fs/exists? (fs/path tmp ".claude"))))
    (check "worktree-settings[pi]: swarmforge.autoCompactPct"       (str/includes? content "autoCompactPct"))
    (check "worktree-settings[pi]: swarmforge.autoCompactWindow"    (str/includes? content "autoCompactWindow"))
    (check "worktree-settings[pi]: compaction.enabled true"         (str/includes? content "\"enabled\" : true"))
    (check "worktree-settings[pi]: no advisor key"                  (not (str/includes? content "advisorModel"))))
  (fs/delete-tree (fs/path tmp)))

;;; write-persona-skill-file! (exercises resolve-prompt-bundle transitively)

(let [root (str (fs/create-temp-dir {:prefix "test-persona-root-"}))
      wt   (str (fs/create-temp-dir {:prefix "test-persona-wt-"}))]
  (fs/create-dirs (fs/path root "swarmforge" "constitution" "articles"))
  (spit (str (fs/path root "swarmforge" "constitution.prompt")) "# Constitution\n")
  (spit (str (fs/path root "swarmforge" "constitution" "articles" "workflow.prompt")) "# Workflow\n")
  (fs/create-dirs (fs/path root "swarmforge" "roles"))
  (spit (str (fs/path root "swarmforge" "roles" "coder.prompt")) "# Coder\n")
  (let [ctx {:working-dir (fs/path root)
             :constitution-file (fs/path root "swarmforge" "constitution.prompt")
             :roles-dir (fs/path root "swarmforge" "roles")}
        skill-file (str (fs/path wt ".agents" "skills" "swarm-persona" "SKILL.md"))]
    (write-persona-skill-file! ctx "coder" wt)
    (let [content (slurp skill-file)]
      (check "persona-skill: SKILL.md created in .agents/skills" (fs/exists? (fs/path skill-file)))
      (check "persona-skill: no .claude copy"                   (not (fs/exists? (fs/path wt ".claude" "skills" "swarm-persona" "SKILL.md"))))
      (check "persona-skill: name: swarm-persona"           (str/includes? content "name: swarm-persona"))
      (check "persona-skill: bundles role file"             (str/includes? content "swarmforge/roles/coder.prompt"))
      (check "persona-skill: bundles constitution article"  (str/includes? content "swarmforge/constitution"))
      (check "persona-skill: no AGENTS.md in bundle (pi loads it natively)" (not (str/includes? content "<file path=\"AGENTS.md\">")))))
  (fs/delete-tree (fs/path root))
  (fs/delete-tree (fs/path wt)))

;;; link-skills! (formerly link-curator-skills!) — directory-level symlink

(let [tmp (str (fs/create-temp-dir {:prefix "test-curator-"}))]
  (fs/create-dirs (fs/path tmp ".agents" "skills" "my-skill"))
  (spit (str (fs/path tmp ".agents" "skills" "my-skill" "SKILL.md")) "test\n")
  (link-skills! tmp)
  (check "link-skills: .claude/skills is a symlink"       (fs/sym-link? (fs/path tmp ".claude" "skills")))
  (check "link-skills: symlink resolves to .agents/skills" (fs/exists? (fs/path tmp ".claude" "skills" "my-skill")))
  ;; legacy real-dir is replaced by the symlink
  (fs/create-dirs (fs/path tmp ".claude" "skills-legacy"))
  (spit (str (fs/path tmp ".claude" "skills-legacy" "x")) "x\n")
  (fs/delete (fs/path tmp ".claude" "skills"))
  (fs/copy-tree (fs/path tmp ".claude" "skills-legacy") (fs/path tmp ".claude" "skills"))
  (link-skills! tmp)
  (check "link-skills: replaces existing real dir with symlink" (and (fs/sym-link? (fs/path tmp ".claude" "skills"))
                                                                       (fs/exists? (fs/path tmp ".claude" "skills" "my-skill"))))
  ;; backward-compat alias still works
  (fs/delete (fs/path tmp ".claude" "skills"))
  (link-curator-skills! tmp)
  (check "link-curator-skills! alias delegates to link-skills!" (fs/sym-link? (fs/path tmp ".claude" "skills")))
  (fs/delete-tree (fs/path tmp)))

;;; Report

(println)
(if (empty? @failures)
  (do (println (str "All " "fork.bb extension tests passed.")) (System/exit 0))
  (do (println (str (count @failures) " failure(s): " (str/join ", " @failures)))
      (System/exit 1)))
