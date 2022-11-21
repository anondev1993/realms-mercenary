# Mercenary module for Realms on Starknet

<p align="center">
<img src="imgs/mercenary.jpeg" width="90%" height="90%" alt="Prosper Empire">
</p>

# Introduction
Bounties can be placed on any Realm in order to add an incentive for other Realms to attack it. 
An outsider Realm can then claim the bounty by performing a successful attack on this targeted Realm, 
via the Mercenary module. The bounty is transferred to this “mercenary” in the event of a winning outcome. 
This strategy allows Reamls to increase their influence on all Realms of the Atlas: in case a Realm wants 
to weaken an enemy located far across the land, it could simply issue a bounty on this enemy and wait 
for other Realms to handle the hard work for him.

# Testing
All the entrypoints of the Empires contract are tested in Protostar.

| Entrypoint                   | Tested in Protostar |
| ---------------------------- | ------------------- |
| issue_bounty                 | ❌                  |
| hire_mercenary               | ❌                  |
