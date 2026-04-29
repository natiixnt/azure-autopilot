"""
Identity helpers: probe what an MI/SP has access to, assign roles, list assignments.

Usage:
    python identity.py probe --resource-id <umi-or-sp-resource-id>
    python identity.py assign --principal <object-id> --role <role-name-or-guid> --scope <resource-id>
    python identity.py kv-grant --umi <umi-resource-id> --kv <kv-resource-id>
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

# Common role mapping (display name → GUID)
ROLE_GUIDS = {
    "Contributor": "b24988ac-6180-42a0-ab88-20f7382dd24c",
    "Reader": "acdd72a7-3385-48ef-bd42-f606fba81ae7",
    "Owner": "8e3af657-a8ff-443c-a75c-2fe8c4bcb635",
    "Key Vault Secrets User": "4633458b-17de-408a-b874-0445c86b69e6",
    "Key Vault Secrets Officer": "b86a8fe4-44ce-4948-aee5-eccb2c155cd7",
    "Key Vault Crypto User": "12338af0-0e69-4776-bea7-57ae8d297424",
    "Storage Blob Data Reader": "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1",
    "Storage Blob Data Contributor": "ba92f5b4-2d11-453d-a403-e96b0029c9fe",
    "Storage Blob Data Owner": "b7e6dc6d-f1e8-4753-8033-0f276bb0955b",
    "AcrPull": "7f951dda-4ed3-4680-a7ca-43fe172d538d",
    "AcrPush": "8311e382-0749-4cb8-b61a-304f252e45ec",
    "Cognitive Services OpenAI User": "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd",
    "Cognitive Services OpenAI Contributor": "a001fd3d-188f-4b5d-821b-7da978bf7442",
    "Search Index Data Reader": "1407120a-92aa-4202-b7e9-c0e197c71c8f",
    "Search Index Data Contributor": "8ebe5a00-799e-43f5-93ac-243d3dce84a7",
    "Cosmos DB Built-in Data Reader": "00000000-0000-0000-0000-000000000001",
    "Cosmos DB Built-in Data Contributor": "00000000-0000-0000-0000-000000000002",
    "Azure Service Bus Data Sender": "69a216fc-b8fb-44d8-bc22-1f3c2cd27a39",
    "Azure Service Bus Data Receiver": "4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0",
    "Azure Event Hubs Data Sender": "2b629674-e913-4c01-ae53-ef4638d8f975",
    "Azure Event Hubs Data Receiver": "a638d3c7-ab3a-418d-83e6-5f17a39d4fde",
}


def az(cmd: list[str]) -> str:
    """Run az CLI and return stdout. Errors propagate."""
    r = subprocess.run(["az"] + cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"[az error] {' '.join(cmd)}", file=sys.stderr)
        print(r.stderr, file=sys.stderr)
        sys.exit(r.returncode)
    return r.stdout


def resolve_role(role: str) -> str:
    return ROLE_GUIDS.get(role, role)  # if not in map, assume it's already a GUID


def probe(resource_id: str):
    """Show what role assignments principal has and across what scopes."""
    # Resource id might be UMI or SP appId; figure out principalId
    print(f"── Probing {resource_id} ──")
    if "/userAssignedIdentities/" in resource_id:
        info = json.loads(az(["resource", "show", "--ids", resource_id]))
        principal_id = info["properties"]["principalId"]
        client_id = info["properties"]["clientId"]
        print(f"UMI principalId: {principal_id}, clientId: {client_id}")
    else:
        # Assume it's an app/SP id
        principal_id = resource_id

    print("\n── Role assignments ──")
    out = az(["role", "assignment", "list", "--assignee", principal_id, "--all",
              "--query", "[].{role:roleDefinitionName, scope:scope}", "-o", "table"])
    print(out)


def assign(principal: str, role: str, scope: str):
    role_guid = resolve_role(role)
    az(["role", "assignment", "create",
        "--assignee-object-id", principal,
        "--assignee-principal-type", "ServicePrincipal",
        "--role", role_guid,
        "--scope", scope])
    print(f"Granted '{role}' to {principal} on {scope}")


def kv_grant(umi: str, kv: str):
    """Convenience: grant 'Key Vault Secrets User' from a UMI to a KV."""
    info = json.loads(az(["resource", "show", "--ids", umi]))
    principal_id = info["properties"]["principalId"]
    assign(principal_id, "Key Vault Secrets User", kv)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd")

    p_probe = sub.add_parser("probe")
    p_probe.add_argument("--resource-id", required=True)

    p_assign = sub.add_parser("assign")
    p_assign.add_argument("--principal", required=True)
    p_assign.add_argument("--role", required=True)
    p_assign.add_argument("--scope", required=True)

    p_kv = sub.add_parser("kv-grant")
    p_kv.add_argument("--umi", required=True)
    p_kv.add_argument("--kv", required=True)

    p_roles = sub.add_parser("roles", help="List known role name → GUID mapping")

    args = p.parse_args()

    if args.cmd == "probe":
        probe(args.resource_id)
    elif args.cmd == "assign":
        assign(args.principal, args.role, args.scope)
    elif args.cmd == "kv-grant":
        kv_grant(args.umi, args.kv)
    elif args.cmd == "roles":
        for name, guid in sorted(ROLE_GUIDS.items()):
            print(f"{name:50s}  {guid}")
    else:
        p.print_help()


if __name__ == "__main__":
    main()
