# Anti-Patterns

Caught across configuration reviews. Do not reintroduce.

## Configuration

| DO NOT | DO INSTEAD | Why |
|--------|-----------|-----|
| Hardcode API keys in TOML | Use `{{ env.VAR }}` syntax | Security — keys must never be committed |
| Use `provider = "Provider"` (capitalized) | Use `provider = "openai"` (lowercase) | Aura expects lowercase provider names |
| Omit `[agent]` section | Always include `name` and `system_prompt` | Agent won't start without identity |
| Set `turn_depth = 0` | Use `turn_depth = 1` minimum or omit for default | Zero disables all tool use |
| Use `transport = "http"` or `"sse"` | Use `transport = "http_streamable"` or `"stdio"` | Only two valid transports: `http_streamable` and `stdio` |
| Put MCP config under `[mcp.servers]` (no name) | Use `[mcp.servers.my_server_name]` | Each server needs a unique key |
| Reference localhost MCP URLs in Docker examples | Use Docker network names or host.docker.internal | Container can't reach host localhost |

## Documentation

| DO NOT | DO INSTEAD | Why |
|--------|-----------|-----|
| Write README without run instructions | Include exact commands to start the agent | Users need copy-paste commands |
| Assume aura is installed | Show both local and Docker run options | Not everyone builds from source |
| Skip prerequisite listing | List required env vars and services | Users waste time debugging missing deps |
| Use relative paths to aura source | Use `~/Documents/GitHub/aura` or describe build steps | Path consistency across docs |

## Examples

| DO NOT | DO INSTEAD | Why |
|--------|-----------|-----|
| Create examples without inline TOML comments | Comment every non-obvious setting | Self-documenting configs (DD-04) |
| Copy production configs with real URLs | Use placeholder URLs with clear labels | Examples must work in any environment |
| Mix multiple features in a "basic" example | Keep basic examples minimal, one concept each | Progressive complexity aids learning |
| Create example without testing it starts | Validate `CONFIG_PATH=<path> aura-web-server` works | Broken examples destroy trust |
| Use deprecated aura config fields | Check `aura-config/src/config.rs` for current schema | Config schema evolves with aura releases |
