# Legacy Repository Review and Migration

The earlier lab repositories are research inputs, not codebases to merge
wholesale. Their history may contain duplicated automation, obsolete versions,
or material unsuitable for a public flagship repository.

## Review inventory

- `advanced_vagrant`, `vagrantlab`, and `vb` — retain only reusable lessons;
- `ansible-lab` — extract conventions and tests, not duplicated roles;
- `jenkins-lab`, `flask-cd`, and `geekestan-cicd` — extract delivery scenarios;
- `k8s-lab` and `kubernetes-lab` — keep K3s experiments separate and use
  Kubespray for the flagship;
- `terraform-modules` — review module contracts and licensing;
- `puppet_lab` — archive unless a concrete compatibility use case appears;
- `myDesktop` — keep personal workstation concerns outside platform scope.

## Clean-room migration process

1. Scan the old repository and all reachable branches for credentials, private
   keys, state, internal URLs, and personal data.
2. Write the desired behavior and acceptance test without copying source.
3. Implement the behavior against current upstream interfaces in this repository.
4. Credit public inspiration where appropriate; never cite inaccessible private
   employer code as an upstream dependency.
5. Rotate exposed credentials before archiving or publishing an old repository.
6. Archive superseded repositories with a pointer here only after the replacement
   capability is demonstrably available.

The private Baufi repositories are experience sources only. Their code, naming,
and internal topology must not be copied into this project.
