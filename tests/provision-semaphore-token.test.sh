#!/usr/bin/env bash
# Covers stored-token validation and replacement without contacting either API.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVISIONER="$REPO_ROOT/scripts/provision-semaphore-token.sh"

export BAO_ADDR=http://bao.invalid
export BAO_TOKEN=test-bao-token
export DEPLOY_HOST=stubbed-docker-host
export TEST_NEW_TOKEN=replacement-token-123456
TEST_CASE=''
TEST_KV_JSON=''
TEST_STORED_TOKEN=''
TEST_EXPECT_API=''
TEST_API_STATUS=''
TEST_MINT=''
# Per profile: the KV v2 data URL, the field, the minting login, and whether the
# leaf/user exist yet. Defaults are the admin profile's.
TEST_KV_URL="$BAO_ADDR/v1/secret/data/apps/semaphore"
TEST_FIELD=semaphore_api_token
TEST_LOGIN='admin'
TEST_READ_STATUS=200
TEST_USER_EXISTS=yes
TEST_PROFILE=''
export TEST_CASE TEST_KV_JSON TEST_STORED_TOKEN TEST_EXPECT_API TEST_API_STATUS TEST_MINT
export TEST_KV_URL TEST_FIELD TEST_LOGIN TEST_READ_STATUS TEST_USER_EXISTS

curl() {
  local method=GET content_type='' request_body='' url='' config_seen=no
  while (($#)); do
    case "$1" in
      -X|--request) method="$2"; shift 2 ;;
      -K|--config) config_seen=yes; shift 2 ;;
      -H|--header)
        case "$2" in
          'Content-Type: '*) content_type="${2#Content-Type: }" ;;
        esac
        shift 2
        ;;
      -d|--data|--data-binary)
        if [[ "$2" == @- ]]; then request_body="$(command cat)"; else request_body="$2"; fi
        shift 2
        ;;
      -o|--output|-w|--write-out|--max-time) shift 2 ;;
      -*) shift ;;
      *) url="$1"; shift ;;
    esac
  done

  case "$url" in
    "$TEST_KV_URL")
      [[ "$config_seen" == yes ]] || return 60
      [[ "$*" != *"$BAO_TOKEN"* && "$*" != *"$TEST_NEW_TOKEN"* ]] || return 61
      if [[ "$method" == POST ]]; then
        [[ "$TEST_READ_STATUS" == 404 && "$content_type" == application/json ]] || return 66
        printf '%s' "$request_body" | jq -e --arg f "$TEST_FIELD" --arg t "$TEST_NEW_TOKEN" \
          '.data | keys == [$f] and .[$f] == $t' >/dev/null 2>&1 || return 67
      elif [[ "$method" == PATCH ]]; then
        [[ "$content_type" == application/merge-patch+json ]] || return 61
        [[ "$TEST_CASE" == empty || "$TEST_CASE" == unauthorized ]] || return 62
        local merged
        merged="$(jq -cn --argjson existing "$TEST_KV_JSON" --argjson patch "$request_body" \
          '$existing.data.data * $patch.data')"
        printf '%s' "$request_body" | jq -e --arg f "$TEST_FIELD" \
          '.data | keys == [$f]' >/dev/null 2>&1 || return 63
        printf '%s' "$merged" | jq -e --arg f "$TEST_FIELD" --arg t "$TEST_NEW_TOKEN" \
          '.[$f] == $t and .other_key == "preserved"' >/dev/null 2>&1 || return 64
      elif [[ "$TEST_READ_STATUS" == 404 ]]; then
        printf '%s\n%s' '{"errors":[]}' 404
      else
        printf '%s\n%s' "$TEST_KV_JSON" 200
      fi
      ;;
    *) return 65 ;;
  esac
}

docker() {
  case "$*" in
    *'user get --login '*)
      [[ "$*" == *"--login $TEST_LOGIN" ]] || return 77
      [[ "$TEST_USER_EXISTS" == yes ]] || return 1
      ;;
    *'users token create'*)
      [[ "$TEST_MINT" == allowed ]] || return 71
      [[ "$*" == *"--login $TEST_LOGIN "* ]] || return 78
      printf '%s\n' "$TEST_NEW_TOKEN"
      ;;
    *'exec -i semaphore sh -c'* )
      [[ "$TEST_EXPECT_API" == yes ]] || return 72
      local config
      local api_path="\${SEMAPHORE_WEB_ROOT%/}/api/projects"
      config="$(command cat)"
      [[ "$*" == *"$api_path"* ]] || return 73
      [[ "$*" != *"$TEST_STORED_TOKEN"* ]] || return 74
      [[ "$config" == *"header = \"Authorization: Bearer $TEST_STORED_TOKEN\""* ]] || return 75
      printf '%s' "$TEST_API_STATUS"
      ;;
    *) return 76 ;;
  esac
}
export -f curl docker

run_case() {
  local name="$1" expected_status="$2" expected_text="$3" output status
  if output="$(bash "$PROVISIONER" $TEST_PROFILE 2>&1)"; then status=0; else status=$?; fi
  if [[ "$status" != "$expected_status" ]] || [[ "$output" != *"$expected_text"* ]]; then
    echo "FAIL $name (exit $status; expected $expected_status and '$expected_text')" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  for secret in "$TEST_STORED_TOKEN" "$TEST_NEW_TOKEN"; do
    if [[ -n "$secret" && "$output" == *"$secret"* ]]; then
      echo "FAIL $name (token value appeared in output)" >&2
      exit 1
    fi
  done
  echo "ok   $name"
}

TEST_CASE=empty
TEST_KV_JSON='{"data":{"data":{"semaphore_api_token":"","other_key":"preserved"}}}'
TEST_STORED_TOKEN=''
TEST_EXPECT_API=no
TEST_API_STATUS=''
TEST_MINT=allowed
run_case 'empty field mints and patches the token' 0 'wrote semaphore_api_token'

TEST_CASE=valid
TEST_KV_JSON='{"data":{"data":{"semaphore_api_token":"stored-valid-token-123456","other_key":"preserved"}}}'
TEST_STORED_TOKEN=stored-valid-token-123456
TEST_EXPECT_API=yes
TEST_API_STATUS=200
TEST_MINT=forbidden
run_case 'valid stored token is reused' 0 'is valid at secret/apps/semaphore'

TEST_CASE=unauthorized
TEST_KV_JSON='{"data":{"data":{"semaphore_api_token":"stored-revoked-token-123456","other_key":"preserved"}}}'
TEST_STORED_TOKEN=stored-revoked-token-123456
TEST_EXPECT_API=yes
TEST_API_STATUS=401
TEST_MINT=allowed
run_case '401 mints and patches a replacement' 0 'wrote semaphore_api_token'

TEST_CASE=server-error
TEST_KV_JSON='{"data":{"data":{"semaphore_api_token":"stored-token-123456789","other_key":"preserved"}}}'
TEST_STORED_TOKEN=stored-token-123456789
TEST_EXPECT_API=yes
TEST_API_STATUS=503
TEST_MINT=forbidden
run_case '5xx fails without minting' 1 'validation returned HTTP 503'

# Agent profile: task_runner-only user, published to its exact agent-tier leaf.
TEST_PROFILE=agent
TEST_KV_URL="$BAO_ADDR/v1/agent-tier/data/semaphore-write"
TEST_FIELD=SEMAPHORE_AGENT_WRITE_TOKEN
TEST_LOGIN=semaphore-agent

TEST_CASE=agent-first-run
TEST_KV_JSON=''
TEST_READ_STATUS=404
TEST_STORED_TOKEN=''
TEST_EXPECT_API=no
TEST_API_STATUS=''
TEST_MINT=allowed
TEST_USER_EXISTS=yes
run_case 'agent: absent leaf mints for the agent login and creates the leaf' 0 \
  'wrote SEMAPHORE_AGENT_WRITE_TOKEN to agent-tier/semaphore-write'

TEST_CASE=empty
TEST_KV_JSON='{"data":{"data":{"SEMAPHORE_AGENT_WRITE_TOKEN":"","other_key":"preserved"}}}'
TEST_READ_STATUS=200
TEST_USER_EXISTS=no
TEST_MINT=forbidden
run_case 'agent: missing user is a clean skip without minting' 0 \
  "user 'semaphore-agent' does not exist yet"

TEST_CASE=valid
TEST_KV_JSON='{"data":{"data":{"SEMAPHORE_AGENT_WRITE_TOKEN":"stored-agent-token-123456","other_key":"preserved"}}}'
TEST_STORED_TOKEN=stored-agent-token-123456
TEST_EXPECT_API=yes
TEST_API_STATUS=200
TEST_USER_EXISTS=yes
run_case 'agent: valid stored token is reused' 0 'is valid at agent-tier/semaphore-write'

TEST_CASE=unauthorized
TEST_API_STATUS=401
TEST_USER_EXISTS=no
TEST_MINT=forbidden
run_case 'agent: rejected token with a missing user fails without minting' 1 \
  "user 'semaphore-agent' no longer exists"

TEST_PROFILE=bogus
run_case 'unknown profile is rejected' 2 'usage: provision-semaphore-token.sh [agent]'

echo 'provision-semaphore-token: all checks passed'
