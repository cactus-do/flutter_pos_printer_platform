package com.cactus.flutter_pos_printer_platform.usb

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.*
import android.os.Build
import android.os.Handler
import android.util.Base64
import android.util.Log
import java.nio.charset.Charset
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean


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

    // ======= Worker infra =======
    private val writeQueue = LinkedBlockingQueue<ByteArray>(500)
    private var writeExecutor: java.util.concurrent.ExecutorService? = null
    private val running = AtomicBoolean(false)


    private var readThread: Thread? = null
    private val reading = AtomicBoolean(false)

    fun isConnected(): Boolean = connection != null

    // =====================================================
    // CONNECT
    // =====================================================

    suspend fun connect(): Boolean {
        if (connection != null) return true

        if (!usbManager.hasPermission(device)) {
            Log.d("UsbPrinter", "Requesting permission for device: ${device.deviceName}")
            val intent = Intent("com.flutter_pos_printer.USB_PERMISSION")
            intent.setPackage(context.packageName)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val permissionIntent = PendingIntent.getBroadcast(context, 0, intent, flags)
            
            // Register a deferred result and wait for it
            val deferred = UsbPermissionManager.registerRequest(device.deviceName)
            usbManager.requestPermission(device, permissionIntent)
            
            notifyState(3) // Permission Needed
            val granted = deferred.await()
            if (!granted) {
                notifyState(5) // Permission Denied
                return false
            }
            notifyState(4) // Permission Granted

        }



        if (!findEndpoints()) {
            Log.e("UsbPrinter", "No bulk endpoint found")
            return false
        }

        val conn = usbManager.openDevice(device) ?: return false


        if (!conn.claimInterface(iface!!, true)) {
            conn.close()
            return false
        }

        connection = conn
        startWriteWorker()
        startReadThread()

        notifyState(2) // Connected
        return true
    }

    // =====================================================
    // PRINT API
    // =====================================================

    fun printText(text: String): Boolean =
        enqueue(text.toByteArray(Charset.forName("UTF-8")))

    fun printRaw(base64: String): Boolean =
        enqueue(Base64.decode(base64, Base64.DEFAULT))

    fun printBytes(bytes: ArrayList<Int>): Boolean =
        enqueue(bytes.map { it.toByte() }.toByteArray())

    private fun enqueue(data: ByteArray): Boolean {
        if (!running.get()) return false
        val success = writeQueue.offer(data)
        if (!success) {
            Log.e("UsbPrinter", "Write queue full, dropping data")
        }
        return success
    }


    // =====================================================
    // WRITE WORKER
    // =====================================================

    private fun startWriteWorker() {
        if (running.get()) return
        running.set(true)

        if (writeExecutor == null || writeExecutor!!.isShutdown) {
            writeExecutor = Executors.newSingleThreadExecutor()
        }

        writeExecutor?.execute {

            while (running.get()) {
                try {
                    val data = writeQueue.take()
                    writeInternal(data)
                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    Log.e("UsbPrinter", "Write error: ${e.message}")
                }
            }
        }
    }

    private fun writeInternal(data: ByteArray) {
        val conn = connection ?: return
        val out = epOut ?: return

        val res = conn.bulkTransfer(out, data, data.size, 10_000)

        if (res < 0) {
            Log.e("UsbPrinter", "bulkTransfer failed")
        }
    }

    // =====================================================
    // READ THREAD
    // =====================================================

    private fun startReadThread() {
        if (epIn == null || reading.get()) return

        reading.set(true)

        readThread = Thread {
            val buffer = ByteArray(1024)

            while (reading.get()) {
                try {
                    val conn = connection ?: break
                    val bytes = conn.bulkTransfer(epIn, buffer, buffer.size, 200)

                    if (bytes > 0) {
                        handler.obtainMessage(
                            2,
                            mapOf(
                                "address" to device.deviceName,
                                "data" to buffer.copyOf(bytes)
                            )
                        ).sendToTarget()
                    }
                } catch (e: Exception) {
                    break
                }
            }
        }

        readThread?.start()
    }

    private fun stopReadThread() {
        reading.set(false)
        readThread?.interrupt()
        readThread = null
    }

    // =====================================================
    // CLOSE
    // =====================================================

    fun close() {
        running.set(false)
        writeExecutor?.shutdownNow()
        writeExecutor = null
        writeQueue.clear()


        stopReadThread()

        connection?.releaseInterface(iface)
        connection?.close()
        connection = null

        notifyState(0) // Disconnected
    }

    // =====================================================
    // ENDPOINT DISCOVERY
    // =====================================================

    private fun findEndpoints(): Boolean {
        Log.d("UsbPrinter", "Scanning ${device.interfaceCount} interfaces for ${device.deviceName}")
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            Log.d("UsbPrinter", "Interface $i: class=${intf.interfaceClass}, subclass=${intf.interfaceSubclass}, protocol=${intf.interfaceProtocol}")

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
                Log.d("UsbPrinter", "Selected Interface $i (Class: ${intf.interfaceClass}) and Bulk OUT: ${epOut?.address}")
                return true
            }
        }
        Log.e("UsbPrinter", "No bulk OUT endpoint found after scanning all interfaces")
        return false
    }


    private fun notifyState(state: Int) {
        handler.obtainMessage(
            1,
            mapOf(
                "address" to device.deviceName,
                "state" to state
            )
        ).sendToTarget()
    }
}