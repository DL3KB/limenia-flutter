package eu.limenia.limenia_device

import android.content.Context
import android.content.pm.PackageManager
import com.google.android.gms.tasks.Task
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityException
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Play Integrity standard requests for the device connector of Limenia. Never logs tokens. */
class LimeniaDevicePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // The prepared token provider, kept per cloud project number and shared by
    // concurrent requests. All access happens on the main thread.
    private var provider: Task<StandardIntegrityTokenProvider>? = null
    private var providerProject = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "eu.limenia/limenia_device")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        provider = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isSupported" -> result.success(isPlayStoreInstalled())
            "requestToken" -> {
                val requestHash = call.argument<String>("requestHash")
                val projectNumber = call.argument<Number>("cloudProjectNumber")?.toLong()
                if (requestHash.isNullOrEmpty() || projectNumber == null || projectNumber <= 0) {
                    result.error(INVALID_ARGUMENT, "requestHash and cloudProjectNumber are required", null)
                    return
                }
                requestToken(requestHash, projectNumber, retry = true, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun isPlayStoreInstalled(): Boolean =
        try {
            context.packageManager.getPackageInfo(PLAY_STORE, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }

    private fun provider(projectNumber: Long): Task<StandardIntegrityTokenProvider> {
        val cached = provider
        if (cached != null && providerProject == projectNumber && !(cached.isComplete && !cached.isSuccessful)) {
            return cached
        }
        val request = PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(projectNumber).build()
        val prepared = IntegrityManagerFactory.createStandard(context).prepareIntegrityToken(request)
        provider = prepared
        providerProject = projectNumber
        return prepared
    }

    private fun requestToken(requestHash: String, projectNumber: Long, retry: Boolean, result: Result) {
        val prepared = provider(projectNumber)
        prepared
            .onSuccessTask { p -> p.request(StandardIntegrityTokenRequest.builder().setRequestHash(requestHash).build()) }
            .addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    result.success(task.result.token())
                    return@addOnCompleteListener
                }
                val e = task.exception
                if (retry && e is StandardIntegrityException &&
                    e.errorCode == StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID
                ) {
                    // The provider expired: prepare a new one, once.
                    if (provider === prepared) provider = null
                    requestToken(requestHash, projectNumber, retry = false, result)
                } else {
                    fail(e, result)
                }
            }
    }

    private fun fail(e: Exception?, result: Result) {
        if (e !is StandardIntegrityException) {
            result.error(FAILED, e?.message ?: "Play Integrity failed", null)
            return
        }
        val code = when (e.errorCode) {
            StandardIntegrityErrorCode.API_NOT_AVAILABLE,
            StandardIntegrityErrorCode.PLAY_STORE_NOT_FOUND,
            StandardIntegrityErrorCode.PLAY_SERVICES_NOT_FOUND -> UNSUPPORTED
            StandardIntegrityErrorCode.CLOUD_PROJECT_NUMBER_IS_INVALID,
            StandardIntegrityErrorCode.REQUEST_HASH_TOO_LONG -> INVALID_ARGUMENT
            else -> FAILED
        }
        result.error(code, e.message, e.errorCode)
    }

    private companion object {
        const val PLAY_STORE = "com.android.vending"
        const val UNSUPPORTED = "unsupported"
        const val INVALID_ARGUMENT = "invalid_argument"
        const val FAILED = "failed"
    }
}
