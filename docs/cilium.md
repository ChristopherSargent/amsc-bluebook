● Cilium CNI Chaining Mode

  Background: what a CNI does                                                                                                                                                        
  Every pod in Kubernetes needs an IP address and a network interface. The Container Network Interface (CNI) plugin is the component responsible for wiring that up — it runs when
   a pod starts, creates the veth pair, assigns the IP, and sets up routing.

  On EKS, AWS installs its own CNI by default: the AWS VPC CNI (aws-node DaemonSet). It assigns each pod a real VPC IP address directly from an ENI (Elastic Network Interface)   
  attached to the node. This is what makes pods routable within your VPC without a tunnel or overlay — other AWS services, RDS, etc., can reach pods directly by IP.

  The problem Cilium solves

  The AWS VPC CNI only handles IP assignment. It provides no:
  - Network policy enforcement — it ignores NetworkPolicy resources entirely (or relies on iptables via kube-proxy, which is slow and hard to debug)
  - Observability — no visibility into which pods are talking to which, what was allowed or denied, or L7 traffic detail
  - L7-aware policy — can't filter by HTTP method, path, or gRPC service name

  Cilium provides all of that, but it also has its own IP management system. The question is: do you replace the AWS VPC CNI entirely, or run both?

  CNI chaining mode: running both

  The config in the file chooses the "run both" approach:

  cni:
    chainingMode: aws-cni   # Cilium inserts itself after VPC CNI in the chain
    exclusive: false         # don't evict the aws-node DaemonSet

  ipam:
    mode: kubernetes         # let VPC CNI assign IPs; Cilium doesn't touch IPAM

  routingMode: native        # no tunnels — use VPC routing directly
  endpointRoutes:
    enabled: true            # program per-pod routes via eBPF instead of iptables

  When a pod starts, the chain fires in order:

  Pod starts
    → VPC CNI runs first
        assigns a real VPC IP to the pod's veth interface
        sets up the ENI mapping
    → Cilium runs second (chained)
        attaches eBPF programs to the pod's network interface
        enforces NetworkPolicy and CiliumNetworkPolicy at the kernel level
        feeds flow data into Hubble for observability
    → Pod is running with a VPC IP and eBPF policy enforcement

  The VPC CNI still owns the IP — pods keep real VPC IPs, stay routable within the VPC, and nothing about the existing networking breaks. Cilium just intercepts all traffic at   
  the eBPF layer to enforce policy and record flows.

  The alternative: full ENI mode (the comment at the bottom)

  The comment describes replacing the VPC CNI entirely:

  cni:
    chainingMode: none   # Cilium is the only CNI
  ipam:
    mode: eni            # Cilium manages ENI attachment and IP allocation itself

  Then you delete the aws-node DaemonSet so the VPC CNI stops running. Cilium takes over everything — IP assignment, routing, and policy. The result is fewer moving parts, better
   performance (one agent instead of two), and access to Cilium's more advanced IPAM features.

  The reason this isn't the default here is operational risk: switching CNI modes on a live cluster requires draining all nodes and is effectively disruptive. Chaining mode works
   without any node disruption and is safe to apply to an existing cluster. For a new cluster being stood up from scratch, ENI mode is the better long-term choice if you want    
  full Cilium.

  Summary
```
  ┌─────────────────────┬────────────────────────────────┬──────────────────────────────┐
  │                     │    Chaining mode (current)     │      ENI mode (comment)      │
  ├─────────────────────┼────────────────────────────────┼──────────────────────────────┤
  │ IP assignment       │ AWS VPC CNI                    │ Cilium                       │
  ├─────────────────────┼────────────────────────────────┼──────────────────────────────┤
  │ Network policy      │ Cilium eBPF                    │ Cilium eBPF                  │
  ├─────────────────────┼────────────────────────────────┼──────────────────────────────┤
  │ Observability       │ Cilium / Hubble                │ Cilium / Hubble              │
  ├─────────────────────┼────────────────────────────────┼──────────────────────────────┤
  │ Pod IPs             │ Real VPC IPs                   │ Real VPC IPs                 │
  ├─────────────────────┼────────────────────────────────┼──────────────────────────────┤
  │ Disruption to apply │ None                           │ Requires node drain          │
  ├─────────────────────┼────────────────────────────────┼──────────────────────────────┤
  │ Agents running      │ aws-node + cilium              │ cilium only                  │
  ├─────────────────────┼────────────────────────────────┼──────────────────────────────┤
  │ Best for            │ Existing clusters / lower risk │ New clusters / cleaner setup │
  └─────────────────────┴────────────────────────────────┴──────────────────────────────┘
```