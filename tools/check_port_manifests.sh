#!/bin/bash -e

directory="${1:?Usage: check_port_manifests.sh DIRECTORY}"
shopt -s nullglob
manifests=("$directory"/*.ports.json)
if [[ ${#manifests[@]} == 0 ]]; then
    echo "ERROR: no port manifests in ${directory}" >&2
    exit 1
fi
read -r low high < /proc/sys/net/ipv4/ip_local_port_range

printf 'EXAMPLE\tSERVICE\tPORT\tTARGET\tPROTO\tALLOCATED\n'
jq -sr 'add | sort_by(.example, .service, .port)[] |
    [.example, .service, .port, .target, .proto, .allocated] | @tsv' "${manifests[@]}"

jq -se --argjson low "$low" --argjson high "$high" '
    add as $ports
    | ([$ports[] | select(.allocated != true)
        | "\(.example): unallocated port \(.port)"]
       + [$ports[] | select(.port < $low or .port > $high)
          | "\(.example): port \(.port) outside \($low)-\($high)"]
       + [$ports | group_by(.port)[] |
          (map(.example) | unique) as $examples | select($examples | length > 1)
          | "port \(.[0].port) shared by \($examples | join(", "))"]) as $errors
    | if $errors | length > 0 then error($errors | join("\n"))
      else true end
' "${manifests[@]}" > /dev/null
