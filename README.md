[![Discord](https://badgen.net/badge/icon/discord?icon=discord&label)](https://discord.gg/uQnjZhZPfu)
[![Twitter](https://badgen.net/badge/icon/twitter?icon=twitter&label)](https://twitter.com/LootRealms)

<!-- badges -->
<p>
  <a href="https://starkware.co/">
    <img src="https://img.shields.io/badge/powered_by-StarkWare-navy">
  </a>
  <a href="https://github.com/anonmyous-author/anonymous-code/blob/main/LICENSE.md">
    <img src="https://img.shields.io/badge/license-MIT-black">
  </a>
</p>

# Mercenary module for Realms

<p align="center">
<img src="imgs/mercenary-module.jpeg" width="90%" height="90%" alt="Prosper Empire">
</p>

# Introduction

Mercenary is a module built for the [Realms Settling Game](https://github.com/BibliothecaForAdventurers/realms-contracts). The Realms project is developed around the idea of composable modules. Any developer can write a module and propose it to the community.
If the community decides to include it within the game, the module will receive write access to the other modules and the game expands.

# Mercenary Module

This module allows anyone to place one or more bounties on another Realm. Multiple bounties can be placed on one Realm and these can be paid in either $LORDS or in-game resources. Once a player attacks and wins against a Realm, he will automatically receive all the bounties placed on that Realm.
This strategy allows players to increase their influence on all Realms of the Atlas:

- in case a Realm wants to weaken an enemy located too far across the map
- in case a Realm does not have enough armies

# Technical Spec

A more detailed description of the contract can be found [here](https://alpine-blarney-4cc.notion.site/Mercenaries-Technical-Spec-4f8549ff1e284b3b9a34a90e65a755b3).

# Testing

All the entrypoints of the Mercenary contract are tested in Protostar.

| Entrypoint        | Tested in Protostar |
| ----------------- | ------------------- |
| issue_bounty      | ✅                  |
| claim_bounties    | ✅                  |
| remove_bounty     | ✅                  |
| transfer_dev_fees | ✅                  |
