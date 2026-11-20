package com.keqdroid.keqdroid

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

// через него плитка узнаёт о смене статуса: сервис зовёт notifyChange, у плитки ContentObserver
class VpnStatusProvider : ContentProvider() {

    companion object {
        const val AUTHORITY = "com.keqdroid.keqdroid.vpnstatus"
        val STATUS_URI: Uri = Uri.parse("content://$AUTHORITY/status")
    }

    // журнал заводим тут: провайдер создаётся раньше службы и плитки
    override fun onCreate(): Boolean {
        context?.let { NativeLog.init(it) }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0
}
