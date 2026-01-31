# bash-ai

[![Tests](https://github.com/Jevs21/bash-ai/actions/workflows/test.yml/badge.svg)](https://github.com/Jevs21/bash-ai/actions/workflows/test.yml)

A lightweight bash script that provides a unified interface for interacting with multiple AI providers. Route prompts to local models (Ollama), OpenAI, Anthropic, or Claude Code CLI using a single consistent command.


## Features

- Single interface for multiple AI providers
- Supports piped input or direct prompts
- Configurable via environment variables or CLI flags
- No dependencies beyond `curl` and `jq`

## Prerequisites

- [jq](https://jqlang.github.io/jq/) - Required for JSON parsing


## Usage

```bash
# Direct prompt
./ai.sh --prompt "Explain recursion in one sentence"

# Piped input
echo "What is 2+2?" | ./ai.sh

# Specify provider and model
./ai.sh --provider openai --model gpt-4o --prompt "Hello"

# Show usage stats (tokens, duration, speed)
./ai.sh --prompt "Hello" --usage
# Output:
# Hello! How can I help you today?
# ---
# time: 2s | in: 12 | out: 8 | tok/s: 15
```

### Options

| Option | Description |
|--------|-------------|
| `--provider <name>` | AI provider: `local`, `ollama`, `openai`, `anthropic`, `claude` |
| `--model <model>` | Model name (uses provider default if omitted) |
| `--prompt <text>` | Prompt text (or pipe to stdin) |
| `--timeout <sec>` | Request timeout in seconds (default: 120) |
| `--usage` | Show usage stats after response (tokens, duration, speed) |

## Environment Variables

### Required (provider-specific)

| Variable | Required For | Description |
|----------|--------------|-------------|
| `AI_OPENAI_API_KEY` | `openai` | Your OpenAI API key |
| `AI_ANTHROPIC_API_KEY` | `anthropic` | Your Anthropic API key |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_PROVIDER` | `local` | Default provider when not specified |
| `AI_TIMEOUT` | `120` | Request timeout in seconds |
| `AI_OLLAMA_HOST` | `http://localhost:11434` | Ollama server URL |
| `AI_OPENAI_API_BASE` | `https://api.openai.com/v1` | OpenAI API base URL |
| `AI_ANTHROPIC_API_BASE` | `https://api.anthropic.com/v1` | Anthropic API base URL |

### Default Models by Provider

| Provider | Default Model |
|----------|---------------|
| `local` / `ollama` | `gemma3:4b` |
| `openai` | `gpt-4o` |
| `anthropic` | `claude-sonnet-4-20250514` |
| `claude` | CLI default |

## Testing

Requires [bats-core](https://github.com/bats-core/bats-core): `brew install bats-core` or `apt install bats`

```bash
bats tests/
```

## Example Script

The included `example.sh` demonstrates the use case that inspired the script: categorizing financial transactions using a local Ollama model.

```bash
./example.sh transactions.txt output.txt
```

**What it does:**
1. Reads a file containing transaction descriptions (one per line)
2. Sends each transaction to the local AI model with a categorization prompt
3. Caches results to avoid duplicate API calls for identical transactions
4. Outputs categories to a file and displays progress

This example shows how `ai.sh` can be integrated into shell scripts for batch processing tasks. 