#!/usr/bin/env luajit
local path = require 'ext.path'
local JavaASMDex = require 'java.asmdex'
local asm = JavaASMDex:fromAsm[[
.class public io.github.thenumbernine.NativeCallback
.super java.lang.Object
.method public <init> ()V
	invoke-direct Ljava/lang/Object; <init> ()V
	return-void
.end method
.method public static native run (JLjava/lang/Object;)Ljava/lang/Object;
]]
print(require'ext.tolua'(asm))
path'NativeCallback.dex':write(asm:compile())
require 'ext.os'.exec('/home/aya/Android/Sdk/build-tools/36.0.0/dexdump NativeCallback.dex')
