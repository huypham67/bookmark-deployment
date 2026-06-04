.PHONY: help gen-keys setup up down logs ps health restart clean purge deploy-vm vm-keys vm-setup vm-logs vm-down shell-db shell-redis env-check

# Variables
DOCKER_COMPOSE := docker-compose
KEY_DIR := ./bookmark-service/keys
PRIVATE_KEY := $(KEY_DIR)/private.pem
PUBLIC_KEY := $(KEY_DIR)/public.pem
VM_USER ?= root
VM_HOST ?= 103.118.29.77
VM_PATH ?= /home/$(VM_USER)/deployment
SSH := ssh $(VM_USER)@$(VM_HOST)
SCP := scp -r

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

help: ## Display this help message
	@echo "$(BLUE)Bookmark Service - Deployment Makefile$(NC)"
	@echo "$(BLUE)======================================$(NC)"
	@echo ""
	@echo "$(GREEN)Local Development:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v 'vm-' | awk 'BEGIN {FS = ":.*?## "} {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)VM Deployment:$(NC)"
	@grep -E '^vm-[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Configuration:$(NC)"
	@echo "  Set VM credentials with:"
	@echo "    make vm-setup VM_USER=ubuntu VM_HOST=your-server-ip"
	@echo ""

# ==================== KEY GENERATION ====================

gen-keys: ## Generate RSA keys for JWT (local)
	@echo "$(BLUE)Generating RSA keys...$(NC)"
	@mkdir -p $(KEY_DIR)
	@if [ -f $(PRIVATE_KEY) ]; then \
		echo "$(YELLOW)⚠️  Keys already exist at $(KEY_DIR)$(NC)"; \
		read -p "Do you want to regenerate? (y/N) " -n 1 -r; \
		echo; \
		if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
			echo "$(YELLOW)Cancelled.$(NC)"; \
			exit 1; \
		fi; \
	fi
	@echo "$(BLUE)Generating private key (2048-bit RSA)...$(NC)"
	@openssl genrsa -out $(PRIVATE_KEY) 2048
	@echo "$(BLUE)Extracting public key...$(NC)"
	@openssl rsa -in $(PRIVATE_KEY) -pubout -out $(PUBLIC_KEY)
	@chmod 600 $(PRIVATE_KEY)
	@chmod 644 $(PUBLIC_KEY)
	@echo "$(GREEN)✓ Keys generated successfully!$(NC)"
	@echo "  Private Key: $(PRIVATE_KEY)"
	@echo "  Public Key: $(PUBLIC_KEY)"
	@ls -lah $(KEY_DIR)/

verify-keys: ## Verify RSA keys are valid
	@echo "$(BLUE)Verifying keys...$(NC)"
	@if [ ! -f $(PRIVATE_KEY) ] || [ ! -f $(PUBLIC_KEY) ]; then \
		echo "$(RED)✗ Keys not found!$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Private Key:$(NC)"
	@openssl pkey -in $(PRIVATE_KEY) -text -noout | head -3
	@echo "$(GREEN)Public Key:$(NC)"
	@openssl pkey -in $(PUBLIC_KEY) -text -noout | head -3
	@echo "$(GREEN)✓ Keys are valid!$(NC)"

# ==================== ENVIRONMENT SETUP ====================

env-check: ## Check if environment files exist
	@echo "$(BLUE)Checking environment files...$(NC)"
	@missing=0; \
	for env_file in postgres/.env bookmark-service/.env config/cloudflared.env; do \
		if [ -f $$env_file ]; then \
			echo "$(GREEN)✓$(NC) $$env_file"; \
		else \
			echo "$(YELLOW)⚠$(NC) $$env_file (missing)"; \
			missing=1; \
		fi; \
	done; \
	if [ $$missing -eq 1 ]; then \
		echo "$(YELLOW)Run 'make setup' to create them$(NC)"; \
	fi

setup: ## Setup environment files and generate keys
	@echo "$(BLUE)Setting up deployment environment...$(NC)"
	@mkdir -p $(KEY_DIR)
	@if [ ! -f postgres/.env ]; then \
		echo "$(YELLOW)Creating postgres/.env...$(NC)"; \
		cp postgres/.env.example postgres/.env 2>/dev/null || echo "POSTGRES_USER=bookmark\nPOSTGRES_PASSWORD=changeme\nPOSTGRES_DB=bookmark_db" > postgres/.env; \
	fi
	@if [ ! -f bookmark-service/.env ]; then \
		echo "$(YELLOW)Creating bookmark-service/.env...$(NC)"; \
		cp bookmark-service/.env.example bookmark-service/.env 2>/dev/null || echo "SERVICE_PORT=3000\nDATABASE_URL=postgres://bookmark:changeme@bookmark-db:5432/bookmark_db" > bookmark-service/.env; \
	fi
	@make gen-keys
	@echo "$(GREEN)✓ Environment setup complete!$(NC)"

# ==================== DOCKER COMPOSE COMMANDS ====================

up: ## Start all services
	@echo "$(BLUE)Starting services...$(NC)"
	@$(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Services started!$(NC)"
	@sleep 3
	@$(MAKE) ps

down: ## Stop all services
	@echo "$(BLUE)Stopping services...$(NC)"
	@$(DOCKER_COMPOSE) down
	@echo "$(GREEN)✓ Services stopped!$(NC)"

logs: ## View real-time logs
	@$(DOCKER_COMPOSE) logs -f

logs-service: ## View bookmark-service logs
	@$(DOCKER_COMPOSE) logs -f bookmark-service

logs-db: ## View database logs
	@$(DOCKER_COMPOSE) logs -f bookmark-db

logs-redis: ## View Redis logs
	@$(DOCKER_COMPOSE) logs -f redis

ps: ## Show running containers
	@echo "$(BLUE)Container Status:$(NC)"
	@$(DOCKER_COMPOSE) ps

restart: ## Restart all services
	@echo "$(BLUE)Restarting services...$(NC)"
	@$(DOCKER_COMPOSE) restart
	@echo "$(GREEN)✓ Services restarted!$(NC)"
	@sleep 2
	@$(MAKE) ps

restart-service: ## Restart bookmark-service
	@echo "$(BLUE)Restarting bookmark-service...$(NC)"
	@$(DOCKER_COMPOSE) restart bookmark-service
	@echo "$(GREEN)✓ Service restarted!$(NC)"

# ==================== HEALTH & DIAGNOSTICS ====================

health: ## Check service health
	@echo "$(BLUE)Checking service health...$(NC)"
	@echo ""
	@echo "$(YELLOW)API Health Check:$(NC)"
	@curl -s http://localhost/health | jq . 2>/dev/null || curl -s http://localhost/health || echo "$(RED)✗ API unavailable$(NC)"
	@echo ""
	@echo "$(YELLOW)Container Status:$(NC)"
	@$(DOCKER_COMPOSE) ps
	@echo ""
	@echo "$(YELLOW)Service Logs (last 5 lines):$(NC)"
	@$(DOCKER_COMPOSE) logs --tail=5

status: ## Show detailed service status
	@echo "$(BLUE)Deployment Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)Docker Containers:$(NC)"
	@docker ps --filter "label!=com.docker.compose.project" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep bookmark || echo "No running containers"
	@echo ""
	@echo "$(YELLOW)Volumes:$(NC)"
	@docker volume ls 2>/dev/null | grep bookmark || echo "No volumes found"
	@echo ""
	@echo "$(YELLOW)Networks:$(NC)"
	@docker network ls 2>/dev/null | grep bookmark || echo "No networks found"

# ==================== DATABASE & CACHE ====================

shell-db: ## Open PostgreSQL shell
	@echo "$(BLUE)Connecting to PostgreSQL...$(NC)"
	@$(DOCKER_COMPOSE) exec bookmark-db psql -U $${POSTGRES_USER:-bookmark} -d $${POSTGRES_DB:-bookmark_db}

shell-redis: ## Open Redis CLI
	@echo "$(BLUE)Connecting to Redis...$(NC)"
	@$(DOCKER_COMPOSE) exec redis redis-cli

backup-db: ## Backup PostgreSQL database
	@echo "$(BLUE)Backing up database...$(NC)"
	@mkdir -p ./backups
	@$(DOCKER_COMPOSE) exec -T bookmark-db pg_dump -U $${POSTGRES_USER:-bookmark} $${POSTGRES_DB:-bookmark_db} > ./backups/backup-$$(date +%Y%m%d-%H%M%S).sql
	@echo "$(GREEN)✓ Backup created!$(NC)"

restore-db: ## Restore PostgreSQL database (provide file: make restore-db FILE=backups/backup.sql)
	@echo "$(BLUE)Restoring database...$(NC)"
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: Please specify FILE=path/to/backup.sql$(NC)"; \
		exit 1; \
	fi
	@$(DOCKER_COMPOSE) exec -T bookmark-db psql -U $${POSTGRES_USER:-bookmark} $${POSTGRES_DB:-bookmark_db} < $(FILE)
	@echo "$(GREEN)✓ Database restored!$(NC)"

# ==================== CLEANUP ====================

clean: ## Stop services and remove containers
	@echo "$(BLUE)Cleaning up containers...$(NC)"
	@$(DOCKER_COMPOSE) down --remove-orphans
	@echo "$(GREEN)✓ Containers removed!$(NC)"

purge: ## Remove containers, volumes, and keys (⚠️  DESTRUCTIVE)
	@echo "$(RED)⚠️  This will delete all data, volumes, and keys!$(NC)"
	@read -p "Are you sure? (yes/no) " -r; \
	if [ "$$REPLY" = "yes" ]; then \
		echo "$(BLUE)Removing containers and volumes...$(NC)"; \
		$(DOCKER_COMPOSE) down -v; \
		echo "$(BLUE)Removing keys...$(NC)"; \
		rm -rf $(KEY_DIR); \
		echo "$(GREEN)✓ Purge complete!$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled.$(NC)"; \
	fi

# ==================== VM DEPLOYMENT ====================

vm-keys: ## Generate RSA keys on VM
	@echo "$(BLUE)Generating RSA keys on VM ($(VM_HOST))...$(NC)"
	@$(SSH) "mkdir -p $(VM_PATH)/$(KEY_DIR) && \
		openssl genrsa -out $(VM_PATH)/$(PRIVATE_KEY) 2048 && \
		openssl rsa -in $(VM_PATH)/$(PRIVATE_KEY) -pubout -out $(VM_PATH)/$(PUBLIC_KEY) && \
		chmod 600 $(VM_PATH)/$(PRIVATE_KEY) && \
		chmod 644 $(VM_PATH)/$(PUBLIC_KEY) && \
		ls -lah $(VM_PATH)/$(KEY_DIR)/"
	@echo "$(GREEN)✓ Keys generated on VM!$(NC)"

vm-setup: ## Deploy application to VM and setup
	@echo "$(BLUE)Setting up deployment on VM ($(VM_USER)@$(VM_HOST))...$(NC)"
	@echo "$(YELLOW)Creating remote directories...$(NC)"
	@$(SSH) "mkdir -p $(VM_PATH)"
	@echo "$(YELLOW)Uploading deployment files...$(NC)"
	@$(SCP) . $(VM_USER)@$(VM_HOST):$(VM_PATH)
	@echo "$(YELLOW)Setting up environment and generating keys...$(NC)"
	@$(SSH) "cd $(VM_PATH) && make setup"
	@echo "$(GREEN)✓ VM setup complete!$(NC)"
	@echo "$(YELLOW)Next: Run 'make vm-up' to start services$(NC)"

vm-up: ## Start services on VM
	@echo "$(BLUE)Starting services on VM...$(NC)"
	@$(SSH) "cd $(VM_PATH) && docker-compose up -d"
	@echo "$(GREEN)✓ Services started on VM!$(NC)"

vm-down: ## Stop services on VM
	@echo "$(BLUE)Stopping services on VM...$(NC)"
	@$(SSH) "cd $(VM_PATH) && docker-compose down"
	@echo "$(GREEN)✓ Services stopped on VM!$(NC)"

vm-logs: ## View logs from VM
	@echo "$(BLUE)Fetching logs from VM...$(NC)"
	@$(SSH) "cd $(VM_PATH) && docker-compose logs --tail=50"

vm-status: ## Check service status on VM
	@echo "$(BLUE)Checking status on VM...$(NC)"
	@$(SSH) "cd $(VM_PATH) && docker-compose ps"

vm-shell: ## SSH into VM
	@echo "$(BLUE)Connecting to VM $(VM_USER)@$(VM_HOST)...$(NC)"
	@$(SSH)

vm-restart: ## Restart services on VM
	@echo "$(BLUE)Restarting services on VM...$(NC)"
	@$(SSH) "cd $(VM_PATH) && docker-compose restart"
	@echo "$(GREEN)✓ Services restarted on VM!$(NC)"

vm-health: ## Check health on VM
	@echo "$(BLUE)Checking health on VM...$(NC)"
	@$(SSH) "curl -s http://localhost/health | jq ."

# ==================== UTILITIES ====================

validate: ## Validate docker-compose configuration
	@echo "$(BLUE)Validating docker-compose.yaml...$(NC)"
	@$(DOCKER_COMPOSE) config --quiet && echo "$(GREEN)✓ Configuration is valid!$(NC)" || echo "$(RED)✗ Configuration has errors!$(NC)"

pull: ## Pull latest images
	@echo "$(BLUE)Pulling latest images...$(NC)"
	@$(DOCKER_COMPOSE) pull
	@echo "$(GREEN)✓ Images updated!$(NC)"

version: ## Show versions
	@echo "$(BLUE)Deployment Tool Versions:$(NC)"
	@docker --version
	@docker-compose --version
	@openssl version

.DEFAULT_GOAL := help
