# Testing Strategy

## Philosophy

- **Config validation over runtime testing** — examples are TOML configs, not code
- **Structural validation first** — TOML must parse, required sections must exist
- **Runtime validation when possible** — if aura binary is available, test startup

## Test Categories

| Category | What It Tests | Required For |
|----------|---------------|--------------|
| TOML syntax | File parses as valid TOML | Every config file |
| Schema validation | Required sections (`[llm]`, `[agent]`) present | Every config file |
| Startup test | Aura-web-server loads the config without errors | New examples (when aura binary available) |
| Docker validation | Docker compose config is valid | Docker/deployment examples |

## Running Validation

```bash
# Validate TOML syntax (requires Python 3.11+)
python3 -c "import tomllib; tomllib.load(open('config.toml', 'rb'))"

# Validate all TOML files in examples/
find examples/ -name "*.toml" -exec python3 -c "
import tomllib, sys
try:
    tomllib.load(open(sys.argv[1], 'rb'))
    print(f'OK: {sys.argv[1]}')
except Exception as e:
    print(f'FAIL: {sys.argv[1]}: {e}')
    sys.exit(1)
" {} \;

# Test aura startup (timeout after 10s — just checks config loads)
CONFIG_PATH=path/to/config.toml timeout 10 aura-web-server 2>&1 | head -20
```

## Do NOT

- Write Rust test code in this repository — this is a config-only repo
- Skip TOML validation before committing
- Assume a config works just because it "looks right" — validate it
- Test with real API keys in CI — use config parse validation only
