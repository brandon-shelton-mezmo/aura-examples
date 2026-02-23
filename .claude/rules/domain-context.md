# Domain Context

## Project Overview

Aura Examples is a companion repository to Mezmo's Aura agent framework. It provides
ready-to-use TOML configuration examples that demonstrate how to configure and deploy
aura agents for various use cases — from simple chatbots to complex multi-tool agents
with RAG pipelines.

The primary audience is developers and SREs who want to deploy aura agents without
writing Rust code. They configure agents entirely through TOML files and run them
via Docker or the aura-web-server binary.

## Key Entities

| Entity | Identifies | Key Fields |
|--------|------------|------------|
| Agent | An aura AI agent instance | name, system_prompt, temperature, turn_depth |
| Provider | LLM backend (OpenAI, Anthropic, etc.) | provider, model, api_key |
| MCP Server | External tool server connected via MCP | transport, url, command |
| Vector Store | RAG knowledge base backend | type (in_memory, qdrant), embedding config |
| Config | A complete TOML configuration file | All sections combined |

## Quick Glossary

| Term | Means | NOT |
|------|-------|----|
| Aura | Mezmo's Rust AI agent framework | The general concept of "aura" |
| MCP | Model Context Protocol — standard for AI tool integration | Message Control Protocol |
| MCP Server | An external process that provides tools to the agent | The aura server itself |
| Transport | How aura connects to MCP servers (HTTP/SSE/STDIO) | Network transport layer |
| Turn Depth | Max LLM reasoning loops before stopping | Conversation turns with user |
| Env Var Resolution | `{{ env.VAR }}` syntax in TOML for runtime values | Shell variable expansion |
| RAG | Retrieval-Augmented Generation via vector stores | Random access generation |
| Provider | LLM service backend (OpenAI, Bedrock, etc.) | Infrastructure provider |
| Config | A TOML file defining an agent's full behavior | Runtime configuration |

## System Boundaries

- Aura Examples provides configuration files and documentation ONLY
- Aura Examples does NOT modify the aura source code
- Aura Examples does NOT include custom Rust code
- The aura binary and its features are defined in `~/Documents/GitHub/aura`
- MCP servers are external services — examples may reference them but don't implement them

## Who Uses This Repository

| Persona | Role | Primary Needs |
|---------|------|---------------|
| Developer | Builds agents for specific use cases | Working config examples, clear docs |
| SRE | Deploys aura in production | Deployment configs, Docker/K8s examples |
| Solutions Engineer | Demos aura to customers | Quick-start examples, impressive demos |
| New Team Member | Learning aura | Progressive examples from simple to complex |
