# Testnet Deployment Record

**Date**: 2026-03-23
**Network**: testnet
**Deployer**: 0x1509b5fdf09296b2cf749a710e36da06f5693ccd5b2144ad643b3a895abcbc4c

## Package IDs

| Package | ID |
|---------|-----|
| industrial_core | `0xe5fa49b0e8cc82b12bf1e26627b9738e57e5431c9d8ccae1c5d8584fb4e5e0a8` |
| work_order | `0x7cef70f7839ee8a86fa5cc488e0aa6c241c126edb2b83e49c487e9cf8aadc029` |
| marketplace | `0xd03d666620eda91417bb3c3479c24dd62e58fc9b2988f5160586e11ba12dee58` |

## UpgradeCap IDs

| Package | UpgradeCap |
|---------|-----------|
| industrial_core | `0xa077695732f739b724950632a6aa585159497d4be1f1b7a6f4566f3d288a85d3` |
| work_order | `0x5a1f36d768247d4379e22228b2d225537683b20136ce4835f59e4f14a18be550` |
| marketplace | `0x6c151d3a407f3fe4a01d90cea3fd3c14619581f8f5765f10e286ffe2246afefc` |

## Shared Objects (init)

| Object | ID |
|--------|-----|
| WorkOrderBoard | `0x36816fca3c2e3792acb87d62ce441d4f2192dd0f355521e8a80e0479d1e4cf84` |
| Marketplace | `0x6b733e0a70b56a81b397c1e1fd7f39a9150923e9fb50f57b04b614418a455a97` |
| MarketplaceAdminCap | `0x3ed52efc5a301d50a9584687471c3b7a4e5bc6147cc88cc8119a70f71ded6e97` |

## E2E Smoke Test Objects

| Object | ID |
|--------|-----|
| Recipe (Tritanium Refining) | `0xfd15bf8c0154e7e603e83481d278a450157b0243787a2841bf45f39e85a9aebe` |
| ProductionLine (Assembly Line Alpha) | `0x4f796546289c932a2b217b47773c893111f2ad3b1455cbbd10a74565592dc151` |
| BlueprintOriginal | `0x7fd8d3ceb3bd965cbf34cf3e5184f018378f2960ff7248a816014e5ff658d10d` |
| WorkOrder (Build Tritanium Batch) | `0xd21559e61d1dc6708105b4c715fc6ee01cc587d9787672d04851007b6bc04b61` |

## Gas Usage

| Package | Gas (MIST) |
|---------|-----------|
| industrial_core | 70,291,480 |
| work_order | 40,811,080 |
| marketplace | 47,293,880 |
| **Total** | **158,396,440** (~0.158 SUI) |

## Transaction Digests

| Action | Digest |
|--------|--------|
| Publish industrial_core | `G7gbs64VaMCjQZPsvopshKR1eh7dQmgHuuqePoz516un` |
| Publish work_order | (see tx log) |
| Publish marketplace | (see tx log) |
| Create Recipe | `GyScm5dDTke289ywTLWYUuvW1Hdiyabc8RmBAqbyZQNc` |
| Create ProductionLine | (see tx log) |
| Mint BPO | (see tx log) |
| List BPO on Marketplace | (see tx log) |
| Create WorkOrder | (see tx log) |
