#!/usr/bin/env bats

# Test suite for ai.sh

setup() {
    # Get the directory where the test file is located
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(dirname "$TEST_DIR")"

    # Create a temporary directory for mocks
    MOCK_DIR="$(mktemp -d)"

    # Save original PATH
    ORIGINAL_PATH="$PATH"

    # Clear environment variables that might interfere
    unset AI_OPENAI_API_KEY
    unset AI_ANTHROPIC_API_KEY
}

teardown() {
    # Restore PATH
    export PATH="$ORIGINAL_PATH"

    # Clean up mock directory
    [[ -d "$MOCK_DIR" ]] && rm -rf "$MOCK_DIR"
}

# Helper to create a mock command
create_mock() {
    local cmd="$1"
    local script="$2"
    echo "$script" > "$MOCK_DIR/$cmd"
    chmod +x "$MOCK_DIR/$cmd"
    export PATH="$MOCK_DIR:$PATH"
}

# =============================================================================
# Help and Usage Tests
# =============================================================================

@test "displays help with --help" {
    run "$PROJECT_ROOT/ai.sh" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: ai"* ]]
    [[ "$output" == *"--provider"* ]]
    [[ "$output" == *"--model"* ]]
    [[ "$output" == *"--prompt"* ]]
}

@test "displays help with -h" {
    run "$PROJECT_ROOT/ai.sh" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: ai"* ]]
}

# =============================================================================
# Argument Parsing Tests
# =============================================================================

@test "fails with unknown option" {
    run "$PROJECT_ROOT/ai.sh" --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: --invalid-option"* ]]
}

# =============================================================================
# Input Methods: Piped Input and Direct Prompts
# =============================================================================

@test "direct prompt: accepts text via --prompt flag" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"choices\":[{\"message\":{\"content\":\"test response\"}}]}"'

    run "$PROJECT_ROOT/ai.sh" --provider openai --prompt "Hello"
    [ "$status" -eq 0 ]
    [[ "$output" == "test response" ]]
}

@test "direct prompt: handles special characters" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}"'

    run "$PROJECT_ROOT/ai.sh" --provider openai --prompt "What's 2+2? It's \"simple\"!"
    [ "$status" -eq 0 ]
}

@test "piped input: accepts single line from echo" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"choices\":[{\"message\":{\"content\":\"piped response\"}}]}"'

    run bash -c 'echo "Hello from stdin" | '"$PROJECT_ROOT/ai.sh"' --provider openai'
    [ "$status" -eq 0 ]
    [[ "$output" == "piped response" ]]
}

@test "piped input: accepts multiline input" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"choices\":[{\"message\":{\"content\":\"multiline ok\"}}]}"'

    run bash -c 'printf "Line 1\nLine 2\nLine 3" | '"$PROJECT_ROOT/ai.sh"' --provider openai'
    [ "$status" -eq 0 ]
    [[ "$output" == "multiline ok" ]]
}

@test "piped input: accepts input from cat" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"choices\":[{\"message\":{\"content\":\"cat ok\"}}]}"'

    # Create a temp file to cat
    echo "content from file" > "$MOCK_DIR/testfile.txt"

    run bash -c 'cat '"$MOCK_DIR/testfile.txt"' | '"$PROJECT_ROOT/ai.sh"' --provider openai'
    [ "$status" -eq 0 ]
    [[ "$output" == "cat ok" ]]
}

@test "piped input: fails on empty input" {
    export AI_OPENAI_API_KEY="test-key"

    run bash -c 'echo -n "" | '"$PROJECT_ROOT/ai.sh"' --provider openai'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Empty prompt"* ]]
}

# =============================================================================
# Provider: OpenAI Tests
# =============================================================================

@test "openai: requires API key" {
    unset AI_OPENAI_API_KEY
    run "$PROJECT_ROOT/ai.sh" --provider openai --prompt "test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AI_OPENAI_API_KEY required"* ]]
}

@test "openai: uses default model gpt-4o" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
# Capture the payload to verify model
for arg in "$@"; do
    if [[ "$arg" == *"gpt-4o"* ]]; then
        echo "{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}"
        exit 0
    fi
done
echo "Model not found in request" >&2
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider openai --prompt "test"
    [ "$status" -eq 0 ]
}

@test "openai: accepts custom model" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *"gpt-3.5-turbo"* ]]; then
        echo "{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}"
        exit 0
    fi
done
echo "Custom model not found" >&2
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider openai --model gpt-3.5-turbo --prompt "test"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Provider: Anthropic Tests
# =============================================================================

@test "anthropic: requires API key" {
    unset AI_ANTHROPIC_API_KEY
    run "$PROJECT_ROOT/ai.sh" --provider anthropic --prompt "test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AI_ANTHROPIC_API_KEY required"* ]]
}

@test "anthropic: uses correct API endpoint" {
    export AI_ANTHROPIC_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *"api.anthropic.com"*"/messages"* ]]; then
        echo "{\"content\":[{\"text\":\"ok\"}]}"
        exit 0
    fi
done
echo "Endpoint not found" >&2
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider anthropic --prompt "test"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Provider: Local/Ollama Tests
# =============================================================================

@test "local: uses ollama endpoint" {
    create_mock "curl" '#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *"localhost:11434"*"/api/generate"* ]]; then
        echo "{\"response\":\"ollama response\"}"
        exit 0
    fi
done
echo "Ollama endpoint not found" >&2
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider local --prompt "test"
    [ "$status" -eq 0 ]
    [[ "$output" == "ollama response" ]]
}

@test "ollama: is alias for local provider" {
    create_mock "curl" '#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *"/api/generate"* ]]; then
        echo "{\"response\":\"ok\"}"
        exit 0
    fi
done
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider ollama --prompt "test"
    [ "$status" -eq 0 ]
}

@test "local: respects AI_OLLAMA_HOST env var" {
    export AI_OLLAMA_HOST="http://custom-host:1234"
    create_mock "curl" '#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *"custom-host:1234"* ]]; then
        echo "{\"response\":\"ok\"}"
        exit 0
    fi
done
echo "Custom host not found" >&2
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider local --prompt "test"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Provider: Claude CLI Tests
# =============================================================================

@test "claude: requires claude CLI" {
    # Build a PATH that excludes claude but keeps essential tools
    local new_path=""
    IFS=':' read -ra dirs <<< "$PATH"
    for dir in "${dirs[@]}"; do
        [[ -x "$dir/claude" ]] || new_path="${new_path:+$new_path:}$dir"
    done

    run env PATH="$new_path" "$PROJECT_ROOT/ai.sh" --provider claude --prompt "test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"claude CLI not found"* ]]
}

@test "claude: calls claude CLI with -p flag" {
    create_mock "claude" '#!/bin/bash
if [[ "$1" == "-p" ]]; then
    cat  # Echo stdin
    exit 0
fi
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider claude --prompt "hello claude"
    [ "$status" -eq 0 ]
}

@test "claude_code: is alias for claude provider" {
    create_mock "claude" '#!/bin/bash
echo "claude_code works"'

    run "$PROJECT_ROOT/ai.sh" --provider claude_code --prompt "test"
    [ "$status" -eq 0 ]
    [[ "$output" == "claude_code works" ]]
}

# =============================================================================
# Invalid Provider Tests
# =============================================================================

@test "fails with unknown provider" {
    run "$PROJECT_ROOT/ai.sh" --provider unknown --prompt "test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown provider: unknown"* ]]
}

# =============================================================================
# Environment Variable Tests
# =============================================================================

@test "uses AI_PROVIDER env var as default" {
    export AI_PROVIDER="anthropic"
    export AI_ANTHROPIC_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *"anthropic.com"* ]]; then
        echo "{\"content\":[{\"text\":\"env var works\"}]}"
        exit 0
    fi
done
exit 1'

    run "$PROJECT_ROOT/ai.sh" --prompt "test"
    [ "$status" -eq 0 ]
    [[ "$output" == "env var works" ]]
}

@test "command line --provider overrides AI_PROVIDER env var" {
    export AI_PROVIDER="anthropic"
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *"openai.com"* ]]; then
        echo "{\"choices\":[{\"message\":{\"content\":\"override works\"}}]}"
        exit 0
    fi
done
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider openai --prompt "test"
    [ "$status" -eq 0 ]
    [[ "$output" == "override works" ]]
}

@test "respects custom timeout" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == "30" ]]; then
        echo "{\"choices\":[{\"message\":{\"content\":\"timeout ok\"}}]}"
        exit 0
    fi
done
echo "Timeout not set correctly" >&2
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider openai --timeout 30 --prompt "test"
    [ "$status" -eq 0 ]
}

# =============================================================================
# API Error Handling Tests
# =============================================================================

@test "handles curl failure gracefully" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
exit 1'

    run "$PROJECT_ROOT/ai.sh" --provider openai --prompt "test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Request failed"* ]]
}

# =============================================================================
# Usage Stats Flag Tests
# =============================================================================

@test "usage: --usage flag is documented in help" {
    run "$PROJECT_ROOT/ai.sh" --help
    [[ "$output" == *"--usage"* ]]
}

@test "usage: no stats shown without --usage flag" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"choices\":[{\"message\":{\"content\":\"response\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"'

    run "$PROJECT_ROOT/ai.sh" --provider openai --prompt "test"
    [ "$status" -eq 0 ]
    [[ "$output" == "response" ]]
    [[ "$output" != *"tokens"* ]]
}

@test "usage: openai shows stats with --usage flag" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"choices\":[{\"message\":{\"content\":\"response\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"'

    run "$PROJECT_ROOT/ai.sh" --provider openai --prompt "test" --usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"response"* ]]
    [[ "$output" == *"in:"* ]]
    [[ "$output" == *"out:"* ]]
    [[ "$output" == *"10"* ]]
    [[ "$output" == *"5"* ]]
}

@test "usage: anthropic shows stats with --usage flag" {
    export AI_ANTHROPIC_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"content\":[{\"text\":\"response\"}],\"usage\":{\"input_tokens\":15,\"output_tokens\":8},\"stop_reason\":\"end_turn\"}"'

    run "$PROJECT_ROOT/ai.sh" --provider anthropic --prompt "test" --usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"response"* ]]
    [[ "$output" == *"in:"* ]]
    [[ "$output" == *"out:"* ]]
    [[ "$output" == *"15"* ]]
    [[ "$output" == *"8"* ]]
}

@test "usage: ollama shows stats with --usage flag" {
    create_mock "curl" '#!/bin/bash
echo "{\"response\":\"ollama response\",\"prompt_eval_count\":12,\"eval_count\":20,\"eval_duration\":1000000000}"'

    run "$PROJECT_ROOT/ai.sh" --provider local --prompt "test" --usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"ollama response"* ]]
    [[ "$output" == *"in:"* ]]
    [[ "$output" == *"out:"* ]]
    [[ "$output" == *"12"* ]]
    [[ "$output" == *"20"* ]]
}

@test "usage: shows duration" {
    export AI_OPENAI_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"choices\":[{\"message\":{\"content\":\"response\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"'

    run "$PROJECT_ROOT/ai.sh" --provider openai --prompt "test" --usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"time:"* ]]
}

@test "usage: shows tokens per second for ollama" {
    create_mock "curl" '#!/bin/bash
echo "{\"response\":\"response\",\"prompt_eval_count\":10,\"eval_count\":20,\"eval_duration\":2000000000}"'

    run "$PROJECT_ROOT/ai.sh" --provider local --prompt "test" --usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"tok/s:"* ]]
}

@test "usage: shows stop reason when available" {
    export AI_ANTHROPIC_API_KEY="test-key"
    create_mock "curl" '#!/bin/bash
echo "{\"content\":[{\"text\":\"response\"}],\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"stop_reason\":\"max_tokens\"}"'

    run "$PROJECT_ROOT/ai.sh" --provider anthropic --prompt "test" --usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"stop:"* ]]
    [[ "$output" == *"max_tokens"* ]]
}

@test "usage: claude provider shows estimated tokens" {
    create_mock "claude" '#!/bin/bash
echo "claude response"'

    run "$PROJECT_ROOT/ai.sh" --provider claude --prompt "test" --usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude response"* ]]
    [[ "$output" == *"~"* ]]
    [[ "$output" == *"in:"* ]]
    [[ "$output" == *"out:"* ]]
}
