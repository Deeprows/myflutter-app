package com.deeprows.footbolive

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

/** Google Cast SDK configuration. Receiver ID is injected by the build patch. */
class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions {
        val id = context.resources.getIdentifier("deeprowss_cast_receiver_app_id", "string", context.packageName)
        val receiverId = if (id != 0) context.getString(id) else "CC1AD845"
        return CastOptions.Builder().setReceiverApplicationId(receiverId).build()
    }
    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}
