#!/usr/bin/env bash
set -euo pipefail

TABLE_FAMILY="inet"
TABLE_NAME="trafficmon"

WG_CLIENTS=("10.7.0.2")
OVPN_CLIENTS=("10.8.0.0/24")

human() {
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$1"
  else
    echo "${1}B"
  fi
}

table_exists() {
  nft list table "$TABLE_FAMILY" "$TABLE_NAME" >/dev/null 2>&1
}

create_table() {
  nft delete table "$TABLE_FAMILY" "$TABLE_NAME" 2>/dev/null || true
  nft add table "$TABLE_FAMILY" "$TABLE_NAME"

  nft add chain "$TABLE_FAMILY" "$TABLE_NAME" input "{ type filter hook input priority -100; policy accept; }"
  nft add chain "$TABLE_FAMILY" "$TABLE_NAME" output "{ type filter hook output priority -100; policy accept; }"
  nft add chain "$TABLE_FAMILY" "$TABLE_NAME" forward "{ type filter hook forward priority -100; policy accept; }"
}

add_counter() {
  local name=$1
  nft add counter "$TABLE_FAMILY" "$TABLE_NAME" "$name"
}

add_rule() {
  local chain=$1
  local rule=$2
  local counter=$3

  nft add rule "$TABLE_FAMILY" "$TABLE_NAME" "$chain" $rule counter name "$counter"
}

install_rules() {
  create_table

  add_counter "p8881_rx"
  add_counter "p8881_tx"
  add_counter "p8882_rx"
  add_counter "p8882_tx"

  add_rule input "tcp dport 8881" "p8881_rx"
  add_rule output "tcp sport 8881" "p8881_tx"
  add_rule input "tcp dport 8882" "p8882_rx"
  add_rule output "tcp sport 8882" "p8882_tx"

  add_counter "wg_rx"
  add_counter "wg_tx"

  add_rule input "udp dport 51820" "wg_rx"
  add_rule output "udp sport 51820" "wg_tx"

  add_counter "ovpn_rx"
  add_counter "ovpn_tx"

  add_rule input "udp dport 64249" "ovpn_rx"
  add_rule output "udp sport 64249" "ovpn_tx"

  local ip
  for ip in "${WG_CLIENTS[@]}"; do
    local name_tx="wg_${ip}_tx"
    local name_rx="wg_${ip}_rx"

    add_counter "$name_tx"
    add_counter "$name_rx"

    add_rule forward "ip saddr $ip" "$name_tx"
    add_rule forward "ip daddr $ip" "$name_rx"
  done

  for ip in "${OVPN_CLIENTS[@]}"; do
    local name_tx="ovpn_${ip}_tx"
    local name_rx="ovpn_${ip}_rx"

    add_counter "$name_tx"
    add_counter "$name_rx"

    add_rule forward "ip saddr $ip" "$name_tx"
    add_rule forward "ip daddr $ip" "$name_rx"
  done
}

get_counter() {
  local name=$1
  nft list counter "$TABLE_FAMILY" "$TABLE_NAME" "$name" 2>/dev/null | grep -oP 'bytes \K[0-9]+' || echo 0
}

show_rules() {
  if ! table_exists; then
    echo "Not installed"
    exit 1
  fi

  local total_rx=0
  local total_tx=0

  show() {
    local name=$1
    local dir=$2
    local bytes

    bytes=$(get_counter "$name")
    printf "%-30s %12s\n" "$name" "$(human "$bytes")"

    if [[ "$dir" == "rx" ]]; then
      total_rx=$((total_rx + bytes))
    else
      total_tx=$((total_tx + bytes))
    fi
  }

  echo "==== PORTS ===="
  show p8881_rx rx
  show p8881_tx tx
  show p8882_rx rx
  show p8882_tx tx

  echo "==== WIREGUARD ===="
  show wg_rx rx
  show wg_tx tx

  echo "==== OPENVPN ===="
  show ovpn_rx rx
  show ovpn_tx tx

  echo "==== WG CLIENTS ===="
  for ip in "${WG_CLIENTS[@]}"; do
    show "wg_${ip}_tx" tx
    show "wg_${ip}_rx" rx
  done

  echo "==== OVPN CLIENTS ===="
  for ip in "${OVPN_CLIENTS[@]}"; do
    show "ovpn_${ip}_tx" tx
    show "ovpn_${ip}_rx" rx
  done

  echo "-----------------------------"
  printf "%-30s %12s\n" "TOTAL RX" "$(human "$total_rx")"
  printf "%-30s %12s\n" "TOTAL TX" "$(human "$total_tx")"
}

reset_rules() {
  nft reset counters table "$TABLE_FAMILY" "$TABLE_NAME" 2>/dev/null || true
}

remove_rules() {
  nft delete table "$TABLE_FAMILY" "$TABLE_NAME" 2>/dev/null || true
}

case "${1:-show}" in
  install) install_rules ;;
  show) show_rules ;;
  reset) reset_rules ;;
  remove) remove_rules ;;
  *)
    echo "Usage: $0 {install|show|reset|remove}"
    exit 1
    ;;
esac
