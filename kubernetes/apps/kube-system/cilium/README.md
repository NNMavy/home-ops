# Cilium

## UniFi BGP

```sh
router bgp 64513
 bgp router-id 172.16.50.254
 no bgp ebgp-requires-policy

 neighbor talos peer-group
 neighbor talos remote-as 64512

 neighbor 172.16.50.11 peer-group talos
 neighbor 172.16.50.12 peer-group talos
 neighbor 172.16.50.13 peer-group talos

 !
 address-family ipv4 unicast
    neighbor talos next-hop-self
    neighbor talos soft-reconfiguration inbound
 exit-address-family
exit⏎
```
