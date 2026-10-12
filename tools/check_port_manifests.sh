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

# A host port is only a collision if the same (port, proto) pair is published
# by two examples: the kernel allocates TCP and UDP ephemeral ports from
# separate pools, so e.g. 32768/tcp and 32768/udp are expected to coexist.
jq -se --argjson low "$low" --argjson high "$high" '
    add as $ports
    | ([$ports[] | select(.allocated != true)
        | "\(.example): unallocated port \(.port)/\(.proto)"]
       + [$ports[] | select(.port < $low or .port > $high)
          | "\(.example): port \(.port)/\(.proto) outside \($low)-\($high)"]
       + [$ports | group_by([.port, .proto])[] |
          (map(.example) | unique) as $examples | select($examples | length > 1)
          | "port \(.[0].port)/\(.[0].proto) shared by \($examples | join(", "))"]) as $errors
    | if $errors | length > 0 then error($errors | join("\n"))
      else true end
' "${manifests[@]}" > /dev/null
