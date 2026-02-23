package com.cactus.flutter_pos_printer_platform

import android.app.Activity
import android.content.Context
import android.hardware.usb.UsbDevice
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import androidx.annotation.NonNull
import com.cactus.flutter_pos_printer_platform.usb.USBPrinterService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.BinaryMessenger

/** FlutterPosPrinterPlatformPlugin — USB-only (V2.0) */
class FlutterPosPrinterPlatformPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private val TAG = "FlutterPosPrinterPlatformPlugin"

    private var binaryMessenger: BinaryMessenger? = null
    private var channel: MethodChannel? = null
    private var messageUSBChannel: EventChannel? = null
    private var eventUSBSink: EventChannel.EventSink? = null
    private var dataUSBChannel: EventChannel? = null
    private var eventDataSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var currentActivity: Activity? = null
    lateinit var adapter: USBPrinterService

    private val usbHandler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            super.handleMessage(msg)
            when (msg.what) {
                USBPrinterService.STATE_USB_CONNECTED -> {
                    eventUSBSink?.success(2)
                }
                USBPrinterService.STATE_USB_CONNECTING -> {
                    eventUSBSink?.success(1)
                }
                USBPrinterService.STATE_USB_NONE -> {
                    eventUSBSink?.success(0)
                }
                USBPrinterService.DATA_READ -> {
                    val data = msg.obj as ByteArray
                    Log.d(TAG, "Plugin received raw data from Service: ${data.size} bytes")
                    val intList = data.map { it.toInt() }
                    eventDataSink?.success(intList)
                }
            }
        }
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine")
        binaryMessenger = flutterPluginBinding.binaryMessenger
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine")
        channel?.setMethodCallHandler(null)
        messageUSBChannel?.setStreamHandler(null)
        messageUSBChannel = null
        dataUSBChannel?.setStreamHandler(null)
        dataUSBChannel = null
        if (::adapter.isInitialized) {
            adapter.setHandler(null)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.d(TAG, "onAttachedToActivity")

        context = binding.activity.applicationContext
        currentActivity = binding.activity

        channel = MethodChannel(binaryMessenger!!, METHOD_CHANNEL)
        channel!!.setMethodCallHandler(this)

        messageUSBChannel = EventChannel(binaryMessenger!!, EVENT_CHANNEL_USB)
        messageUSBChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(p0: Any?, sink: EventChannel.EventSink) {
                eventUSBSink = sink
            }
            override fun onCancel(p0: Any?) {
                eventUSBSink = null
            }
        })

        dataUSBChannel = EventChannel(binaryMessenger!!, EVENT_CHANNEL_USB_DATA)
        dataUSBChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(p0: Any?, sink: EventChannel.EventSink) {
                eventDataSink = sink
            }
            override fun onCancel(p0: Any?) {
                eventDataSink = null
            }
        })

        adapter = USBPrinterService.getInstance(usbHandler)
        adapter.init(context)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.d(TAG, "onDetachedFromActivityForConfigChanges")
        currentActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        Log.d(TAG, "onReattachedToActivityForConfigChanges")
        currentActivity = binding.activity
    }

    override fun onDetachedFromActivity() {
        Log.d(TAG, "onDetachedFromActivity")
        currentActivity = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        Log.d(TAG, "method call: ${call.method}")
        when (call.method) {
            "getList" -> {
                getUSBDeviceList(result)
            }
            "connectPrinter" -> {
                val vendor: Int? = call.argument("vendor")
                val product: Int? = call.argument("product")
                val address: String? = call.argument("address")
                connectPrinter(vendor, product, address, result)
            }
            "close" -> {
                closeConn(result)
            }
            "printText" -> {
                val text: String? = call.argument("text")
                printText(text, result)
            }
            "printRawData" -> {
                val raw: String? = call.argument("raw")
                printRawData(raw, result)
            }
            "printBytes" -> {
                val bytesArg = call.argument<Any>("bytes")
                val bytes: ArrayList<Int>? = if (bytesArg is ByteArray) {
                    val list = ArrayList<Int>(bytesArg.size)
                    for (b in bytesArg) {
                        list.add(b.toInt())
                    }
                    list
                } else {
                    @Suppress("UNCHECKED_CAST")
                    bytesArg as? ArrayList<Int>
                }
                printBytes(bytes, result)
            }
            "read" -> {
                val timeout: Int? = call.argument("timeout")
                readBytes(timeout, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun getUSBDeviceList(result: Result) {
        val list = ArrayList<HashMap<*, *>>()
        val usbDevices: List<UsbDevice> = adapter.deviceList
        for (usbDevice in usbDevices) {
            val deviceMap: HashMap<String?, String?> = HashMap()
            deviceMap["name"] = usbDevice.deviceName
            deviceMap["manufacturer"] = usbDevice.manufacturerName
            deviceMap["product"] = usbDevice.productName
            deviceMap["deviceId"] = usbDevice.deviceId.toString()
            deviceMap["vendorId"] = usbDevice.vendorId.toString()
            deviceMap["productId"] = usbDevice.productId.toString()
            list.add(deviceMap)
        }
        result.success(list)
    }

    private fun connectPrinter(vendorId: Int?, productId: Int?, address: String?, result: Result) {
        if (vendorId == null || productId == null) return
        adapter.setHandler(usbHandler)
        if (!adapter.selectDevice(vendorId, productId, address)) {
            Log.d("USBPrinterService", "Could not select device: vendorId=$vendorId, productId=$productId, address=$address")
            result.success(false)
        } else {
            Log.d("USBPrinterService", "Successfully selected device: vendorId=$vendorId, productId=$productId, address=$address")
            result.success(true)
        }
    }

    private fun closeConn(result: Result) {
        adapter.setHandler(usbHandler)
        adapter.closeConnectionIfExists()
        result.success(true)
    }

    private fun printText(text: String?, result: Result) {
        if (text.isNullOrEmpty()) {
            result.success(false)
            return
        }
        Thread {
            adapter.setHandler(usbHandler)
            val success = adapter.printText(text)
            Handler(Looper.getMainLooper()).post {
                result.success(success)
            }
        }.start()
    }

    private fun printRawData(base64Data: String?, result: Result) {
        if (base64Data.isNullOrEmpty()) {
            result.success(false)
            return
        }
        Thread {
            adapter.setHandler(usbHandler)
            val success = adapter.printRawData(base64Data)
            Handler(Looper.getMainLooper()).post {
                result.success(success)
            }
        }.start()
    }

    private fun printBytes(bytes: ArrayList<Int>?, result: Result) {
        if (bytes == null) {
            result.success(false)
            return
        }
        Thread {
            adapter.setHandler(usbHandler)
            val success = adapter.printBytes(bytes)
            Handler(Looper.getMainLooper()).post {
                result.success(success)
            }
        }.start()
    }

    private fun readBytes(timeout: Int?, result: Result) {
        Thread {
            adapter.setHandler(usbHandler)
            val t = timeout ?: 2000
            val data = adapter.readBytes(t)
            Handler(Looper.getMainLooper()).post {
                if (data != null) {
                    val intList = data.map { it.toInt() }
                    result.success(intList)
                } else {
                    result.success(null)
                }
            }
        }.start()
    }

    companion object {
        const val METHOD_CHANNEL = "com.cactus.flutter_pos_printer_platform"
        const val EVENT_CHANNEL_USB = "com.cactus.flutter_pos_printer_platform/usb_state"
        const val EVENT_CHANNEL_USB_DATA = "com.cactus.flutter_pos_printer_platform/usb_data"
    }
}
