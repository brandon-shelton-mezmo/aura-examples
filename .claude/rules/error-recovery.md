# Error Recovery Patterns

## Config Parsing

| Symptom | Cause | Recovery |
|---------|-------|----------|
| `TOML parse error` on startup | Invalid TOML syntax | Validate with `python3 -c "import tomllib; ..."` to find exact line |
| `missing field 'provider'` | `[llm]` section missing provider | Add `provider = "openai"` (or other valid provider) |
| `missing field 'model'` | `[llm]` section missing model | Add `model = "gpt-4o"` (model name for your provider) |
| `unknown field 'X'` | Using deprecated or misspelled config key | Check `aura-config/src/config.rs` for valid fields |
| `env var not found: VAR` | Using `{{ env.VAR }}` but VAR not set | Export the env var: `export VAR=value` |

## MCP Connection

| Symptom | Cause | Recovery |
|---------|-------|----------|
| `connection refused` to MCP server | MCP server not running or wrong URL | Start the MCP server first; check URL and port |
| `timeout` connecting to MCP server | Network issue or server slow to start | Increase timeout; check if server is healthy |
| `invalid transport type` | Wrong transport value in config | Use `"http_streamable"`, `"sse"`, or `"stdio"` |
| MCP tools not appearing | Server connected but no tools listed | Check MCP server actually implements tools; use `--dump-prompt` to debug |

## Docker

| Symptom | Cause | Recovery |
|---------|-------|----------|
| `config.toml not found` in container | Volume mount path wrong | Check `-v $(pwd)/config.toml:/app/config.toml` mount |
| Can't reach host services from container | Using `localhost` in config | Use `host.docker.internal` (Mac/Windows) or Docker network name |
| Container exits immediately | Config error or missing env var | Check logs: `docker logs <container>` |
| Port already in use | Another process on port 3030 | Use `-p 3031:3030` to map different host port |

## Provider Auth

| Symptom | Cause | Recovery |
|---------|-------|----------|
| `401 Unauthorized` from OpenAI | Invalid or expired API key | Regenerate key at platform.openai.com; set `OPENAI_API_KEY` |
| `403 Forbidden` from Bedrock | Missing IAM permissions | Check AWS IAM policy includes `bedrock:InvokeModel*` |
| `connection refused` from Ollama | Ollama not running locally | Start with `ollama serve`; ensure model is pulled |
| `model not found` | Model name wrong for provider | Check provider docs for exact model ID string |
