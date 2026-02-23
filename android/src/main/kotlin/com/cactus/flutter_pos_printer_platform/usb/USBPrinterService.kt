package com.cactus.flutter_pos_printer_platform.usb

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Handler
import android.util.Base64
import android.util.Log
import android.widget.Toast
import com.cactus.flutter_pos_printer_platform.R
import java.nio.charset.Charset
import java.util.*

class USBPrinterService private constructor(private var mHandler: Handler?) {
    private var mContext: Context? = null
    private var mUSBManager: UsbManager? = null
    private var mPermissionIndent: PendingIntent? = null
    private var mUsbDevice: UsbDevice? = null
    private var mUsbDeviceConnection: UsbDeviceConnection? = null
    private var mUsbInterface: UsbInterface? = null
    private var mEndPoint: UsbEndpoint? = null
    private var mEndPointIn: UsbEndpoint? = null
    var state: Int = STATE_USB_NONE
    private var isReading = false
    private var readThread: Thread? = null

    fun setHandler(handler: Handler?) {
        mHandler = handler
    }

    private val mUsbDeviceReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action
            if ((ACTION_USB_PERMISSION == action)) {
                synchronized(this) {
                    val usbDevice: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                        Log.i(
                            LOG_TAG,
                            "Success get permission for device ${usbDevice?.deviceId}, vendor_id: ${usbDevice?.vendorId} product_id: ${usbDevice?.productId}"
                        )
                        mUsbDevice = usbDevice
                        state = STATE_USB_CONNECTED
                        mHandler?.obtainMessage(STATE_USB_CONNECTED)?.sendToTarget()
                    } else {
                        if (usbDevice != null) {
                            Toast.makeText(context, mContext?.getString(R.string.user_refuse_perm) + ": ${usbDevice.deviceName}", Toast.LENGTH_LONG).show()
                        } else {
                            Toast.makeText(context, mContext?.getString(R.string.user_refuse_perm), Toast.LENGTH_LONG).show()
                        }
                        state = STATE_USB_NONE
                        mHandler?.obtainMessage(STATE_USB_NONE)?.sendToTarget()
                    }
                }
            } else if ((UsbManager.ACTION_USB_DEVICE_DETACHED == action)) {

                if (mUsbDevice != null) {
                    Toast.makeText(context, mContext?.getString(R.string.device_off), Toast.LENGTH_LONG).show()
                    closeConnectionIfExists()
                    state = STATE_USB_NONE
                    mHandler?.obtainMessage(STATE_USB_NONE)?.sendToTarget()
                }

            } else if ((UsbManager.ACTION_USB_DEVICE_ATTACHED == action)) {
//                if (mUsbDevice != null) {
//                    Toast.makeText(context, "USB device has been turned off", Toast.LENGTH_LONG).show()
//                    closeConnectionIfExists()
//                }
            }
        }
    }

    fun init(reactContext: Context?) {
        Log.d("USBPrinterService", "init called")
        mContext = reactContext
        mUSBManager = mContext!!.getSystemService(Context.USB_SERVICE) as UsbManager
        val intent = Intent(ACTION_USB_PERMISSION)
        intent.setPackage(mContext?.packageName)
        mPermissionIndent = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            PendingIntent.getBroadcast(mContext, 0, intent, PendingIntent.FLAG_MUTABLE)
        } else {
            PendingIntent.getBroadcast(mContext, 0, intent, 0)
        }
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            mContext!!.registerReceiver(mUsbDeviceReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            mContext!!.registerReceiver(mUsbDeviceReceiver, filter)
        }
        Log.v(LOG_TAG, "ESC/POS Printer initialized")
    }

    fun closeConnectionIfExists() {
        if (mUsbDeviceConnection != null) {
            mUsbDeviceConnection!!.releaseInterface(mUsbInterface)
            mUsbDeviceConnection!!.close()
            mUsbInterface = null
            mEndPoint = null
            mEndPointIn = null
            mUsbDevice = null
            mUsbDeviceConnection = null
        }
    }

    val deviceList: List<UsbDevice>
        get() {
            if (mUSBManager == null) {
                Toast.makeText(mContext, mContext?.getString(R.string.not_usb_manager), Toast.LENGTH_LONG).show()
                return emptyList()
            }
            return ArrayList(mUSBManager!!.deviceList.values)
        }

    fun selectDevice(vendorId: Int, productId: Int, address: String? = null): Boolean {
//        Log.v(LOG_TAG, " status usb ______ $state")
        var needReconnect = false
        if (mUsbDevice == null || mUsbDevice!!.vendorId != vendorId || mUsbDevice!!.productId != productId) {
            needReconnect = true
        } else if (address != null && mUsbDevice!!.deviceName != address) {
            needReconnect = true
        }

        if (needReconnect) {
            synchronized(printLock) {
                closeConnectionIfExists()
                val usbDevices: List<UsbDevice> = deviceList
                for (usbDevice: UsbDevice in usbDevices) {
                    if ((usbDevice.vendorId == vendorId) && (usbDevice.productId == productId)) {
                        if (address != null && usbDevice.deviceName != address) {
                            continue
                        }
                        Log.v(LOG_TAG, "Request for device: vendor_id: " + usbDevice.vendorId + ", product_id: " + usbDevice.productId)
                        closeConnectionIfExists()
                        mUSBManager!!.requestPermission(usbDevice, mPermissionIndent)
                        state = STATE_USB_CONNECTING
                        mHandler?.obtainMessage(STATE_USB_CONNECTING)?.sendToTarget()
                        return true
                    }
                }
                return false
            }
        } else {
            mHandler?.obtainMessage(state)?.sendToTarget()
        }

        return true
    }

    private fun openConnection(): Boolean {
        if (mUsbDevice == null) {
            Log.e(LOG_TAG, "USB Device is not initialized")
            return false
        }
        if (mUSBManager == null) {
            Log.e(LOG_TAG, "USB Manager is not initialized")
            return false
        }
        if (mUsbDeviceConnection != null) {
            return true
        }

        var epOut: UsbEndpoint? = null
        var epIn: UsbEndpoint? = null
        var targetInterface: UsbInterface? = null

        // Improved endpoint discovery: search through all interfaces
        val interfaceCount = mUsbDevice!!.interfaceCount
        Log.d(LOG_TAG, "Scanning $interfaceCount interfaces for endpoints")
        
        for (i in 0 until interfaceCount) {
            val usbInterface = mUsbDevice!!.getInterface(i)
            var currentEpOut: UsbEndpoint? = null
            var currentEpIn: UsbEndpoint? = null

            for (j in 0 until usbInterface.endpointCount) {
                val ep = usbInterface.getEndpoint(j)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                    if (ep.direction == UsbConstants.USB_DIR_OUT) {
                        currentEpOut = ep
                    } else if (ep.direction == UsbConstants.USB_DIR_IN) {
                        currentEpIn = ep
                    }
                }
            }

            // A valid printer interface usually has at least a BULK OUT endpoint.
            // Some specialized printers might not have a BULK IN on the same interface, 
            // but we prefer one that has both.
            if (currentEpOut != null) {
                epOut = currentEpOut
                epIn = currentEpIn
                targetInterface = usbInterface
                // If we found both on this interface, we stop searching
                if (epIn != null) {
                    Log.d(LOG_TAG, "Found both IN and OUT endpoints on interface $i")
                    break
                }
            }
        }

        if (epOut == null || targetInterface == null) {
            Log.e(LOG_TAG, "Failed to find suitable USB BULK OUT endpoint")
            return false
        }

        val usbDeviceConnection = mUSBManager!!.openDevice(mUsbDevice)
        if (usbDeviceConnection == null) {
            Log.e(LOG_TAG, "Failed to open USB Connection")
            return false
        }
        
        // Explicitly set configuration
        try {
            if (mUsbDevice!!.configurationCount > 0) {
                usbDeviceConnection.setConfiguration(mUsbDevice!!.getConfiguration(0))
                Log.d(LOG_TAG, "Set USB Configuration 0")
            }
        } catch (e: Exception) {
            Log.w(LOG_TAG, "Failed to set configuration: ${e.message}")
        }

        return if (usbDeviceConnection.claimInterface(targetInterface, true)) {
            mEndPoint = epOut
            mEndPointIn = epIn
            mUsbInterface = targetInterface
            mUsbDeviceConnection = usbDeviceConnection
            Log.d(LOG_TAG, "Connection opened and interface claimed: OUT=$mEndPoint, IN=$mEndPointIn")
            
            // Give the printer a moment to settle after claiming the interface
            try { Thread.sleep(500) } catch (e: Exception) {}
            
            if (mEndPointIn == null) {
                Log.w(LOG_TAG, "WARNING: This printer might not support reading (No IN endpoint found)")
            } else {
                startReadThread()
            }
            true
        } else {
            usbDeviceConnection.close()
            Log.e(LOG_TAG, "Failed to claim USB interface")
            false
        }
    }

    private fun startReadThread() {
        if (isReading) return
        isReading = true
        readThread = Thread {
            try {
                Log.d(LOG_TAG, "Read thread loop started")
                val buffer = ByteArray(1024)
                while (isReading && mUsbDeviceConnection != null && mEndPointIn != null) {
                    val bytesRead = mUsbDeviceConnection!!.bulkTransfer(mEndPointIn, buffer, buffer.size, 100)
                    if (bytesRead > 0) {
                        val data = buffer.copyOfRange(0, bytesRead)
                        Log.d(LOG_TAG, "Read thread captured ${data.size} bytes: ${data.contentToString()}")
                        val handler = mHandler
                        if (handler != null) {
                            val msg = handler.obtainMessage(DATA_READ, data)
                            handler.sendMessage(msg)
                        } else {
                            Log.w(LOG_TAG, "Read thread captured data but mHandler is null")
                        }
                    } else if (bytesRead < 0 && bytesRead != -1) { // -1 is usually a timeout, which is normal
                        Log.v(LOG_TAG, "Read thread bulkTransfer returned error code: $bytesRead")
                        try { Thread.sleep(100) } catch (e: Exception) { break }
                    }
                }
            } catch (e: Exception) {
                Log.e(LOG_TAG, "Read thread encountered exception: ${e.message}")
            } finally {
                isReading = false
                Log.d(LOG_TAG, "Read thread exited/stopped")
            }
        }
        readThread?.start()
    }

    private fun stopReadThread() {
        isReading = false
        readThread?.interrupt()
        readThread = null
    }

    fun printText(text: String): Boolean {
        Log.v(LOG_TAG, "Printing text")
        val isConnected = openConnection()
        return if (isConnected) {
            synchronized(printLock) {
                val bytes: ByteArray = text.toByteArray(Charset.forName("UTF-8"))
                val b: Int = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, bytes, bytes.size, 100000)
                Log.i(LOG_TAG, "Return code: $b")
                b >= 0
            }
        } else {
            Log.v(LOG_TAG, "Failed to connect to device")
            false
        }
    }

    fun printRawData(data: String): Boolean {
        Log.v(LOG_TAG, "Printing raw data: $data")
        val isConnected = openConnection()
        return if (isConnected) {
            synchronized(printLock) {
                val bytes: ByteArray = Base64.decode(data, Base64.DEFAULT)
                val b: Int = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, bytes, bytes.size, 100000)
                Log.i(LOG_TAG, "Write raw result code: $b")
                b >= 0
            }
        } else {
            Log.v(LOG_TAG, "Failed to connected to device")
            false
        }
    }

    fun printBytes(bytes: ArrayList<Int>): Boolean {
        Log.v(LOG_TAG, "Printing bytes: size=${bytes.size}")
        val isConnected = openConnection()
        if (!isConnected) {
            Log.v(LOG_TAG, "Failed to connected to device")
            return false
        }
        
        val chunkSize = mEndPoint!!.maxPacketSize
        synchronized(printLock) {
            val vectorData: Vector<Byte> = Vector()
            for (i in bytes.indices) {
                val `val`: Int = bytes[i]
                vectorData.add(`val`.toByte())
            }
            val temp: Array<Any> = vectorData.toTypedArray()
            val byteData = ByteArray(temp.size)
            for (i in temp.indices) {
                byteData[i] = temp[i] as Byte
            }

            var success = true
            if (mUsbDeviceConnection != null) {
                if (byteData.size > chunkSize) {
                    var chunks: Int = byteData.size / chunkSize
                    if (byteData.size % chunkSize > 0) {
                        ++chunks
                    }
                    for (i in 0 until chunks) {
                        val fromIndex = i * chunkSize
                        val toIndex = (fromIndex + chunkSize).coerceAtMost(byteData.size)
                        val buffer: ByteArray = Arrays.copyOfRange(byteData, fromIndex, toIndex)
                        val b = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, buffer, buffer.size, 100000)
                        Log.i(LOG_TAG, "Write bytes result code (chunk $i): $b")
                        if (b < 0) {
                            Log.e(LOG_TAG, "Bulk transfer failed at chunk $i: return code $b")
                            success = false
                        }
                    }
                } else {
                    val b = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, byteData, byteData.size, 100000)
                    Log.i(LOG_TAG, "Write bytes result code: $b")
                    if (b < 0) success = false
                }
            }
            return success
        }
    }

    fun readBytes(timeout: Int = 2000): ByteArray? {
        // legacy method, no longer used in stream-based architecture
        return null
    }

    companion object {
        @SuppressLint("StaticFieldLeak")
        private var mInstance: USBPrinterService? = null
        private const val LOG_TAG = "USBPrinterService" // Updated LOG_TAG
        private const val ACTION_USB_PERMISSION = "com.cactus.flutter_pos_printer_platform.USB_PERMISSION"

        // Constants that indicate the current connection state
        const val STATE_USB_NONE = 0 // we're doing nothing
        const val STATE_USB_CONNECTING = 2 // now initiating an outgoing connection
        const val STATE_USB_CONNECTED = 3 // now connected to a remote device

        private val printLock = Any()

        // New constants for connection states and data read
        const val STATE_CONNECTED = 1
        const val STATE_CONNECTING = 2
        const val STATE_NONE = 3
        const val DATA_READ = 4

        fun getInstance(handler: Handler): USBPrinterService {
            Log.d("USBPrinterService", "getInstance called")
            if (mInstance == null) {
                mInstance = USBPrinterService(handler)
            } else {
                mInstance!!.setHandler(handler)
            }
            return mInstance!!
        }
    }
}
