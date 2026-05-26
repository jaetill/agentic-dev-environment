# Changelog

## 0.1.0 (2026-05-26)


### Features

* **actions:** add install-node-deps composite action ([a6ac53f](https://github.com/jaetill/agentic-dev-environment/commit/a6ac53fc76d95241af5d78d41633fcc621a7e540))
* **agents:** finding lifecycle - calibration, deferral, Sentry pickup ([91ab79b](https://github.com/jaetill/agentic-dev-environment/commit/91ab79bc490fb47ecfbe58f35db7c1b3f6c6aadf))
* **ci:** auto-merge job for routine implementer fix PRs (ADR-0021) ([#56](https://github.com/jaetill/agentic-dev-environment/issues/56)) ([41dc8d7](https://github.com/jaetill/agentic-dev-environment/commit/41dc8d789d7f7d949745e339dc486799132caca3))
* **ci:** platform repo runs claude-pr-review on its own PRs (ADR-0019) ([#31](https://github.com/jaetill/agentic-dev-environment/issues/31)) ([18238af](https://github.com/jaetill/agentic-dev-environment/commit/18238af09f1861c645f01d21efa7a37e250103a6))
* **ci:** reconcile claude-pr-review reusable to current 9-job version (ADR-0018) ([#23](https://github.com/jaetill/agentic-dev-environment/issues/23)) ([04f8ed6](https://github.com/jaetill/agentic-dev-environment/commit/04f8ed601da9a628dd813f480c15c2cb621f3aaf))
* **governance:** add CODEOWNERS for workspace self-adoption ([ad6a172](https://github.com/jaetill/agentic-dev-environment/commit/ad6a172dc1c4e97cba5e9de7dc3fab279eda534b))
* initial commit of agentic dev environment platform ([ae9231c](https://github.com/jaetill/agentic-dev-environment/commit/ae9231c96ea20bdc38c120971cc9d8b00dc32382))
* **orchestration:** auto-pick-up human-filed issues + loop runbook ([#26](https://github.com/jaetill/agentic-dev-environment/issues/26)) ([ffa0284](https://github.com/jaetill/agentic-dev-environment/commit/ffa0284720defc88dab90ce7ad6bdcea374c442d))
* **orchestration:** Phase B - triage scheduling, work routing, feature plan-gate ([#17](https://github.com/jaetill/agentic-dev-environment/issues/17)) ([39b5a65](https://github.com/jaetill/agentic-dev-environment/commit/39b5a65fc0f3434e82e0879e765f22cd7c6118c0))
* **orchestration:** run the autonomous loop fleet-wide (ADR-0020) ([#33](https://github.com/jaetill/agentic-dev-environment/issues/33)) ([0a49a10](https://github.com/jaetill/agentic-dev-environment/commit/0a49a10d43c63e869b480798aadd331790a7363e))
* **orchestration:** two daily triage windows — 01:00-04:00 + 09:00-12:00 ([#25](https://github.com/jaetill/agentic-dev-environment/issues/25)) ([f361167](https://github.com/jaetill/agentic-dev-environment/commit/f361167b464ee562519c9d384b50db9d0ced66a9))
* **orchestration:** wire ADR-0023's origin-based autonomy boundary ([#79](https://github.com/jaetill/agentic-dev-environment/issues/79)) ([d4a2711](https://github.com/jaetill/agentic-dev-environment/commit/d4a27119248d5e3c893c1f4ecf9e38f274553269))
* **orchestration:** wire the self-modification + feedback loop (ADR-0019) ([#30](https://github.com/jaetill/agentic-dev-environment/issues/30)) ([feebc1a](https://github.com/jaetill/agentic-dev-environment/commit/feebc1a2410173551f8e3f541700db5172f8daa1))
* **platform:** ADR-0017 async orchestration + CODEOWNERS ([#16](https://github.com/jaetill/agentic-dev-environment/issues/16)) ([ab14e16](https://github.com/jaetill/agentic-dev-environment/commit/ab14e160c79445433941c11ba877f162aa8e6842))


### Bug Fixes

* **ci:** add workflow_call trigger to test-modules-plan.yml ([#4](https://github.com/jaetill/agentic-dev-environment/issues/4)) ([0a34d96](https://github.com/jaetill/agentic-dev-environment/commit/0a34d969cfef6787668ae83f40a7588e5b61c219))
* **ci:** ci-health watcher auto-closes its issue on recovery ([#21](https://github.com/jaetill/agentic-dev-environment/issues/21)) ([6bd65a9](https://github.com/jaetill/agentic-dev-environment/commit/6bd65a98dd68910782e181a990eedee905207495))
* **ci:** claude-code-action runs on non-Node repos + add CI-health watcher ([#19](https://github.com/jaetill/agentic-dev-environment/issues/19)) ([4298feb](https://github.com/jaetill/agentic-dev-environment/commit/4298feb0603087de6ecd504d6570ef5147ce0687))
* **ci:** doc-keeper runs in reviewer-mode ([#28](https://github.com/jaetill/agentic-dev-environment/issues/28)) ([f9f69fc](https://github.com/jaetill/agentic-dev-environment/commit/f9f69fcf8404ee466f3d4c072278b19e63389ad4))
* **ci:** guard npm ci --prefix lambda in the review reusable ([#47](https://github.com/jaetill/agentic-dev-environment/issues/47)) ([d41bcd6](https://github.com/jaetill/agentic-dev-environment/commit/d41bcd690aadaa43fa7075f1579ce46a56773650))
* **ci:** hoist NB comment out of if-block scalar (workflow was unparseable) ([#3](https://github.com/jaetill/agentic-dev-environment/issues/3)) ([becc0b8](https://github.com/jaetill/agentic-dev-environment/commit/becc0b8ba41be5f4cf5a9c458ad01af8b9b0f2b7))
* **ci:** stop running broken tofu tests on every main push ([#6](https://github.com/jaetill/agentic-dev-environment/issues/6)) ([d044ed7](https://github.com/jaetill/agentic-dev-environment/commit/d044ed718eaa7e328aeee0de9a77cb93dfebb71b))
* **hooks:** set executable bit on all .sh files ([#11](https://github.com/jaetill/agentic-dev-environment/issues/11)) ([a0c801b](https://github.com/jaetill/agentic-dev-environment/commit/a0c801b977061b81b26d88656f68422d3e7a4f45))
* **iac:** repair tofu test fixtures + re-enable push trigger ([#8](https://github.com/jaetill/agentic-dev-environment/issues/8)) ([72947ea](https://github.com/jaetill/agentic-dev-environment/commit/72947eae11e02bf9910c88d22db83c08e67124bc))
* **implementer:** allow fleet-App dispatch; drop API-key fallback ([#45](https://github.com/jaetill/agentic-dev-environment/issues/45)) ([1c0a2fd](https://github.com/jaetill/agentic-dev-environment/commit/1c0a2fd3a55b03ae6f21018c00b7ca699bf8bb0e))
* **orchestration:** add id-token write permission to triage-scan ([#18](https://github.com/jaetill/agentic-dev-environment/issues/18)) ([da9add5](https://github.com/jaetill/agentic-dev-environment/commit/da9add5786609ab5fff984afdb82337eded269be))
* **template:** remove placeholder markdown links from ADR template ([#7](https://github.com/jaetill/agentic-dev-environment/issues/7)) ([3a556e3](https://github.com/jaetill/agentic-dev-environment/commit/3a556e3a4dd58b8505c64abb3fdc13ddaed89681))


### Miscellaneous Chores

* release 0.1.0 ([#14](https://github.com/jaetill/agentic-dev-environment/issues/14)) ([8dbb9f8](https://github.com/jaetill/agentic-dev-environment/commit/8dbb9f80724ec81427cc16e2edc8a68dde9ccd9b))
