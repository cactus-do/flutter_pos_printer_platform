package com.cactus.flutter_pos_printer_platform

import android.app.Activity
import android.content.Context
import android.hardware.usb.UsbDevice
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import androidx.annotation.NonNull
import android.content.IntentFilter
import com.cactus.flutter_pos_printer_platform.usb.UsbPrinterManager
import com.cactus.flutter_pos_printer_platform.usb.UsbReceiver
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*


class FlutterPosPrinterPlatformPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware {

    private val TAG = "FlutterPosPrinterPlugin"

    private var context: Context? = null
    private var activity: Activity? = null

    private lateinit var methodChannel: MethodChannel
    private lateinit var stateChannel: EventChannel
    private lateinit var dataChannel: EventChannel

    private var stateSink: EventChannel.EventSink? = null
    private var dataSink: EventChannel.EventSink? = null

    private lateinit var printerManager: UsbPrinterManager
    private var usbReceiver: UsbReceiver? = null


    companion object {
        const val METHOD_CHANNEL = "com.cactus.flutter_pos_printer_platform"
        const val EVENT_USB_STATE = "com.cactus.flutter_pos_printer_platform/usb_state"
        const val EVENT_USB_DATA = "com.cactus.flutter_pos_printer_platform/usb_data"

        const val MSG_STATE = 1
        const val MSG_DATA = 2
    }

    /** Handler que recibe eventos desde CADA UsbPrinter */
    private val usbHandler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            when (msg.what) {

                MSG_STATE -> {
                    val map = msg.obj as Map<*, *>
                    stateSink?.success(
                        mapOf(
                            "address" to map["address"],
                            "state" to map["state"]
                        )
                    )
                }

                MSG_DATA -> {
                    val map = msg.obj as Map<*, *>
                    val bytes = map["data"] as ByteArray
                    dataSink?.success(
                        mapOf(
                            "address" to map["address"],
                            "data" to bytes.map { it.toInt() }
                        )
                    )
                }
            }
        }
    }

    /* ================= Flutter lifecycle ================= */

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        stateChannel = EventChannel(binding.binaryMessenger, EVENT_USB_STATE)
        dataChannel = EventChannel(binding.binaryMessenger, EVENT_USB_DATA)

        stateChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                stateSink = events
            }

            override fun onCancel(arguments: Any?) {
                stateSink = null
            }
        })

        dataChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                dataSink = events
            }

            override fun onCancel(arguments: Any?) {
                dataSink = null
            }
        })
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        stateSink = null
        dataSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        context = binding.activity.applicationContext
        printerManager = UsbPrinterManager(context!!, usbHandler)
        
        // Register USB Receiver
        usbReceiver = UsbReceiver(printerManager)
        val filter = IntentFilter().apply {
            addAction(android.hardware.usb.UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(android.hardware.usb.UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        context!!.registerReceiver(usbReceiver, filter)
    }

    override fun onDetachedFromActivity() {
        usbReceiver?.let {
            context?.unregisterReceiver(it)
        }
        usbReceiver = null
        activity = null
    }


    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    /* ================= MethodChannel ================= */

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {

            "getList" -> {
                val list = printerManager.listDevices().map { d ->
                    mapOf(
                        "deviceId" to d.deviceId.toString(),
                        "vendorId" to d.vendorId,
                        "productId" to d.productId,
                        "name" to d.deviceName,
                        "manufacturer" to d.manufacturerName,
                        "product" to d.productName,
                        "connected" to printerManager.isConnected(d.deviceName)
                    )
                }


                result.success(list)
            }

            "connectPrinter" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.success(false)
                    return
                }
                result.success(printerManager.connect(address))
            }


            "disconnectPrinter" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.success(false)
                    return
                }
                printerManager.disconnect(address)
                result.success(true)
            }

            "printText" -> {
                val address = call.argument<String>("address")
                val text = call.argument<String>("text")
                if (address == null || text == null) {
                    result.success(false)
                    return
                }
                result.success(printerManager.printText(address, text))
            }

            "printRawData" -> {
                val address = call.argument<String>("address")
                val raw = call.argument<String>("raw")
                if (address == null || raw == null) {
                    result.success(false)
                    return
                }
                result.success(printerManager.printRaw(address, raw))
            }

            "printBytes" -> {
                val address = call.argument<String>("address")
                val bytes = call.argument<ArrayList<Int>>("bytes")
                if (address == null || bytes == null) {
                    result.success(false)
                    return
                }
                result.success(printerManager.printBytes(address, bytes))
            }


            else -> result.notImplemented()
        }
    }
}