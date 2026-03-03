package com.cactus.flutter_pos_printer_platform.usb

import android.content.Context
import android.hardware.usb.*
import android.os.Handler
import android.util.Base64
import android.util.Log
import java.nio.charset.Charset

class UsbPrinter(
    private val context: Context,
    private val device: UsbDevice,
    private val handler: Handler
) {

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private var connection: UsbDeviceConnection? = null
    private var iface: UsbInterface? = null
    private var epOut: UsbEndpoint? = null
    private var epIn: UsbEndpoint? = null

    private val lock = Any()
    private var reading = false
    private var readThread: Thread? = null

    fun isConnected(): Boolean = connection != null

    fun connect(): Boolean {
        Log.d("UsbPrinter", "connect() called for ${device.deviceName}")
        if (connection != null) {
            Log.d("UsbPrinter", "Already connected to ${device.deviceName}")
            return true
        }

        Log.d("UsbPrinter", "Device has ${device.interfaceCount} interfaces")
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            Log.d("UsbPrinter", "Interface $i: class=${intf.interfaceClass}, subclass=${intf.interfaceSubclass}, protocol=${intf.interfaceProtocol}, endpoints=${intf.endpointCount}")
            var out: UsbEndpoint? = null
            var `in`: UsbEndpoint? = null

            for (j in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(j)
                Log.d("UsbPrinter", "  Endpoint $j: type=${ep.type}, direction=${ep.direction}, address=${ep.address}")
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                    if (ep.direction == UsbConstants.USB_DIR_OUT) out = ep
                    if (ep.direction == UsbConstants.USB_DIR_IN) `in` = ep
                }
            }

            if (out != null) {
                iface = intf
                epOut = out
                epIn = `in`
                Log.d("UsbPrinter", "Selected Interface $i and bulk out endpoint: ${epOut?.address}")
                break
            }
        }


        if (iface == null || epOut == null) {
            Log.e("UsbPrinter", "No bulk out endpoint found for ${device.deviceName}")
            return false
        }

        Log.d("UsbPrinter", "Opening device: ${device.deviceName}")
        val conn = usbManager.openDevice(device) ?: run {
            Log.e("UsbPrinter", "Could not open device (permission denied?): ${device.deviceName}")
            return false
        }
        
        Log.d("UsbPrinter", "Claiming interface: ${iface?.id}")
        if (!conn.claimInterface(iface!!, true)) {
            Log.e("UsbPrinter", "Could not claim interface for ${device.deviceName}")
            conn.close()
            return false
        }

        connection = conn
        startReadThread()
        Log.d("UsbPrinter", "Connection established, sending MSG_STATE for ${device.deviceName}")
        // Notify connected: MSG_STATE (1), state: Connected (2)
        handler.obtainMessage(1, mapOf("address" to device.deviceName, "state" to 2)).sendToTarget()
        return true
    }


    fun close() {
        stopReadThread()
        connection?.releaseInterface(iface)
        connection?.close()
        connection = null
        // Notify disconnected: MSG_STATE (1), state: Disconnected (0)
        handler.obtainMessage(1, mapOf("address" to device.deviceName, "state" to 0)).sendToTarget()
    }

    fun printText(text: String): Boolean =
        write(text.toByteArray(Charset.forName("UTF-8")))

    fun printRaw(base64: String): Boolean =
        write(Base64.decode(base64, Base64.DEFAULT))

    fun printBytes(bytes: ArrayList<Int>): Boolean =
        write(bytes.map { it.toByte() }.toByteArray())

    private fun write(data: ByteArray): Boolean {
        synchronized(lock) {
            val conn = connection ?: return false
            val out = epOut ?: return false
            val res = conn.bulkTransfer(out, data, data.size, 10_000)
            return res >= 0
        }
    }

    private fun startReadThread() {
        if (epIn == null || reading) return
        reading = true

        readThread = Thread {
            val buffer = ByteArray(1024)
            while (reading) {
                val conn = connection ?: break
                val bytes = conn.bulkTransfer(epIn, buffer, buffer.size, 200)
                if (bytes > 0) {
                    val dataMap = mapOf(
                        "address" to device.deviceName,
                        "data" to buffer.copyOf(bytes)
                    )
                    handler.obtainMessage(2, dataMap).sendToTarget()
                }
            }
        }
        readThread?.start()
    }

    private fun stopReadThread() {
        reading = false
        readThread?.interrupt()
        readThread = null
    }
}