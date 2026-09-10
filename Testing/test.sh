#!/bin/bash
# ==============================================================================
# webserv interactive test script
#
#   1) tester      — runs the 42 tester binary against the server
#   2) CGI test    — curl checks: static, 404, hello.py, echo.py, cgi_tester
#   3) siege       — load test on static + CGI endpoints
#
# Usage:  ./test.sh
# ==============================================================================

PORT=8082
HOST="127.0.0.1"
BASE="http://${HOST}:${PORT}"

# Resolve folders (script lives in Testing/, server binary one level up)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
WEBSERV="${ROOT_DIR}/webserv"
CONF="${SCRIPT_DIR}/test.conf"

# Point the config at this Testing folder (works regardless of checkout path)
sed -i "s|root .*/Testing;|root ${SCRIPT_DIR};|" "$CONF"
sed -i "s|alias .*/Testing/YoupiBanane;|alias ${SCRIPT_DIR}/YoupiBanane;|" "$CONF"
sed -i "s|interpreter \.sh .*/cgi_tester;|interpreter .sh ${SCRIPT_DIR}/cgi_tester;|" "$CONF"
sed -i "s|interpreter \.bla .*/cgi_tester;|interpreter .bla ${SCRIPT_DIR}/cgi_tester;|" "$CONF"

# ------------------------------------------------------------------------------
# Server management
# ------------------------------------------------------------------------------
server_pid() {
	pgrep -x webserv | head -1
}

start_server() {
	if [ -n "$(server_pid)" ]; then
		echo "[i] webserv already running (pid $(server_pid))"
		return
	fi
	echo "[i] Starting webserv with ${CONF} ..."
	setsid nohup "$WEBSERV" -q "$CONF" >/tmp/webserv_test.log 2>&1 </dev/null &
	sleep 1
	if [ -z "$(server_pid)" ]; then
		echo "[!] webserv failed to start — log output:"
		cat /tmp/webserv_test.log
		exit 1
	fi
	echo "[i] webserv running (pid $(server_pid))"
}

stop_server() {
	local pid="$(server_pid)"
	if [ -n "$pid" ]; then
		# graceful shutdown (SIGTERM breaks the epoll loop)
		kill "$pid" 2>/dev/null
		sleep 0.5
		# make sure it's really gone, along with any CGI helpers
		kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
		pkill -9 -x webserv 2>/dev/null
		pkill -9 -x cgi_tester 2>/dev/null
		echo "[i] webserv stopped"
	fi
}

trap stop_server EXIT

# ------------------------------------------------------------------------------
# Tests
# ------------------------------------------------------------------------------
run_tester() {
	echo
	echo "=== 42 tester (basic checks) ==="
	echo "Note: PUT/HEAD checks may fail — not required here."
	cd "$SCRIPT_DIR"
	./tester "$BASE" || true
	echo
}

run_cgi_tests() {
	echo
	echo "=== CGI tests ==="
	local fail=0

	printf -- "-- GET / (static)        : "
	[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")" = "200" ] \
		&& echo "OK" || { echo "FAIL"; fail=1; }

	printf -- "-- GET /nonexistent      : "
	[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/nonexistent")" = "404" ] \
		&& echo "OK (404)" || { echo "FAIL"; fail=1; }

	printf -- "-- CGI hello.py (query)  : "
	curl -s "${BASE}/cgi-bin/hello.py?name=webserv" | grep -q "Hello, webserv!" \
		&& echo "OK" || { echo "FAIL"; fail=1; }

	printf -- "-- CGI echo.py (POST)    : "
	curl -s -X POST -d 'hello=world' "${BASE}/cgi-bin/echo.py" | grep -q "body=hello=world" \
		&& echo "OK" || { echo "FAIL"; fail=1; }

	printf -- "-- cgi_tester GET        : "
	curl -s "${BASE}/cgi-bin/test.sh" > /dev/null \
		&& echo "OK" || { echo "FAIL"; fail=1; }

	printf -- "-- cgi_tester POST 10KB  : "
	head -c 10000 /dev/urandom | base64 | head -c 10000 > /tmp/ws_body.txt
	curl -s -X POST --data-binary @/tmp/ws_body.txt -o /tmp/ws_resp.txt "${BASE}/cgi-bin/test.sh"
	# cgi_tester uppercases the body — compare case-insensitively
	if cmp -s <(tr '[:lower:]' '[:upper:]' < /tmp/ws_body.txt) \
	         <(tr '[:lower:]' '[:upper:]' < /tmp/ws_resp.txt); then
		echo "OK (10000 bytes echoed)"
	else
		echo "FAIL"; fail=1
	fi

	echo
	[ "$fail" = 0 ] && echo "All CGI tests passed." || echo "Some CGI tests FAILED."
	echo
}

run_siege() {
	echo
	echo "=== siege (load test) ==="
	command -v siege >/dev/null || { echo "siege not installed (sudo apt install siege)"; return; }

	echo "-- static: 25 users x 40 reps --"
	siege -b -c25 -r40 "$BASE/" 2>&1 | tail -14

	echo "-- CGI hello.py: 10 users x 20 reps --"
	siege -b -c10 -r20 "${BASE}/cgi-bin/hello.py" 2>&1 | tail -14

	printf -- "-- server alive after siege: "
	[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")" = "200" ] \
		&& echo "YES" || echo "NO — server died!"
	echo
}

run_siege_custom() {
	echo
	echo "=== siege (custom) ==="
	command -v siege >/dev/null || { echo "siege not installed (sudo apt install siege)"; return; }

	read -rp "URL path [default: /]: " path
	path=${path:-/}
	case "$path" in /*) ;; *) path="/$path" ;; esac

	read -rp "Concurrent users [default: 25]: " users
	users=${users:-25}

	read -rp "Reps per user (empty = time-based) [default: 40]: " reps
	local mode
	if [ -n "$reps" ]; then
		mode="-r$reps"
	else
		read -rp "Duration (e.g. 30S, 2M) [default: 30S]: " duration
		mode="-t${duration:-30S}"
	fi

	read -rp "Benchmark mode - no delays? [Y/n]: " bench
	case "$bench" in n|N) bench="" ;; *) bench="-b" ;; esac

	echo "-- running: siege $bench -c$users $mode ${BASE}${path} --"
	siege $bench -c"$users" $mode "${BASE}${path}" 2>&1 | tail -14

	printf -- "-- server alive after siege: "
	[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")" = "200" ] \
		&& echo "YES" || echo "NO — server died!"
	echo
}

# ------------------------------------------------------------------------------
# Menu
# ------------------------------------------------------------------------------
start_server

while true; do
	echo "==============================="
	echo "  webserv test menu"
	echo "==============================="
	echo "  1) tester   (42 tester)"
	echo "  2) CGI test (curl checks)"
	echo "  3) siege    (load test)"
	echo "  4) siege    (custom parameters)"
	echo "  q) quit (stops server)"
	echo "==============================="
	read -rp "Choose [1/2/3/4/q]: " choice
	case "$choice" in
		1) run_tester ;;
		2) run_cgi_tests ;;
		3) run_siege ;;
		4) run_siege_custom ;;
		q|Q) break ;;
		*) echo "Invalid choice." ;;
	esac
done
