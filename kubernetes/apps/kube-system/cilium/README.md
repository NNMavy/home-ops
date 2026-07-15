# Cilium

## UniFi BGP

```sh
router bgp 65001
 bgp router-id 172.16.60.254
 no bgp ebgp-requires-policy

 neighbor talos peer-group
 neighbor talos remote-as 64512

 neighbor 172.16.60.10 peer-group talos
 neighbor 172.16.60.11 peer-group talos
 neighbor 172.16.60.12 peer-group talos

 !
 address-family ipv4 unicast
    neighbor talos next-hop-self
    neighbor talos soft-reconfiguration inbound
 exit-address-family
exit⏎
```
