# Enclave — launch targets. Run `make` for the list.
.DEFAULT_GOAL := help
COMPOSE := docker compose -f local-stack.yml

.PHONY: help demo demo-up down ps

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

demo: ## Fire the evidence gate live — a real 409, then an earned close
	@bash scripts/demo-refusal.sh

demo-up: ## Bring up the core spine the demo needs (registrar + ux-validate + deps)
	$(COMPOSE) --profile core up -d

ps: ## Show core service health
	$(COMPOSE) --profile core ps

down: ## Stop the stack (data volumes are preserved)
	$(COMPOSE) --profile core down
