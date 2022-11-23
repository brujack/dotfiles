#!/usr/bin/env bash

# tmux \
#   new -s 'bpytop' -c 'bpytop' \; \
#   detach-client \; \
#   new -s 'cyber1' -c 'cd ~/git-repos/cybernetiq/claw_core/terraform-ansible' \; \
#   detach-client \; \
#   new -s 'cyber2' -c 'cd ~/git-repos/cybernetiq/claw_core/terraform-ansible' \; \
#   detach-client \; \
#   new -s 'cone1' -c 'cd ~/git-repos/personal/terraform_ansible' \; \
#   detach-client \; \
#   new -s 'cone2' -c 'cd ~/git-repos/personal/terraform_ansible' \; \
#   detach-client

tmux new -s 'bpytop' -c 'bpytop'
tmux new -s 'cyber1'
tmux new -s 'cyber2'
tmux new -s 'cone1'
tmux new -s 'cone2'
