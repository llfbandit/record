package com.llfbandit.record.permission

fun interface PermissionResultCallback {
    fun onResult(granted: Boolean)
}