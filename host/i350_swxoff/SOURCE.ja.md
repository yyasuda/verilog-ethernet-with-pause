# Source provenance

対象 kernel/package は以下です。

```text
uname -r: 6.8.0-138-generic
linux-image-6.8.0-138-generic: 6.8.0-138.138~22.04.1
linux-headers-6.8.0-138-generic: 6.8.0-138.138~22.04.1
linux-modules-6.8.0-138-generic: 6.8.0-138.138~22.04.1
source package: linux-hwe-6.8 6.8.0-138.138~22.04.1
```

Canonical archive から取得した source package の SHA-256 は `.dsc` 記載値と一致しました。

```text
26512115972bdf017a4ac826cc7d3e9b0ba397d4f85cd330e4e4ff54c78061c8  linux-hwe-6.8_6.8.0.orig.tar.gz
19c8278ca4465856e47cdd26da03be16ddcfa117e6a4f89939127b74290987cf  linux-hwe-6.8_6.8.0-138.138~22.04.1.diff.gz
```

Ubuntu 差分適用後の未変更 `igb` 主要ファイルは以下です。

```text
71dc211c759d26a7915a482a698419812c6a07d9aef45decfca8cefa727ea4b3  Makefile
4c33369c68d5b6f7d0a350ead02bc766be3fee76cd7bb9e2ef07f3cae2527e33  e1000_defines.h
e4ce3e0194e90dc2f118b63cc7a81251f534af5277ea99fbd2464c9206c78c84  igb.h
aad78ebe4fbdf821a93771676fd9f16cccc0f310ca72da41e362b7af58447b1e  igb_main.c
```

`source/` は同じ source package の `drivers/net/ethernet/intel/igb/` 一式をコピーし、`igb_swxoff.patch` を適用したうえで external module 用 Makefile を置いた tree です。stock module や `/lib/modules` 以下は変更していません。
