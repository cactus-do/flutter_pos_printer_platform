package com.sersoluciones.flutter_pos_printer_platform.usb

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
import android.content.pm.PackageManager
import java.nio.charset.Charset
import java.util.*

class USBPrinterService private constructor(private val mHandler: Handler) {
    private var mContext: Context? = null
    private var mUSBManager: UsbManager? = null
    private var mPermissionIndent: PendingIntent? = null
    private var mUsbDevice: UsbDevice? = null
    private var mUsbDeviceConnection: UsbDeviceConnection? = null
    private var mUsbInterface: UsbInterface? = null
    private var mEndPoint: UsbEndpoint? = null
    private val mUsbDeviceReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action
            Log.d(LOG_TAG, "Full Intent: $intent")
            Log.d(LOG_TAG, "onReceive called with action: $action")
            Log.d(LOG_TAG, "Intent extras: ${intent.extras}")
            Log.d(LOG_TAG, "Intent get boolean: ${intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)}")
            if (ACTION_USB_PERMISSION == action) {
                synchronized(this) {
                    val usbDevice: UsbDevice? = if (android.os.Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    }

                    if (usbDevice == null) {
                        Log.e(LOG_TAG, "USB device is null in USB_PERMISSION")
                        return
                    }

                    if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                        Log.i(
                            LOG_TAG,
                            "Success getting permission for device ${usbDevice.deviceId}, vendor_id: ${usbDevice.vendorId}, product_id: ${usbDevice.productId}"
                        )
                        mUsbDevice = usbDevice
                        mHandler.obtainMessage(STATE_USB_CONNECTED).sendToTarget()
                    } else {
                        Log.e(LOG_TAG, "User refused to grant USB permission for device: ${usbDevice.deviceName}")
                        Toast.makeText(
                            context,
                            "User refused to give USB device permission: ${usbDevice.deviceName}",
                            Toast.LENGTH_LONG
                        ).show()
                        mHandler.obtainMessage(STATE_USB_NONE).sendToTarget()
                    }
                }
            } else if (UsbManager.ACTION_USB_DEVICE_DETACHED == action) {
                if (mUsbDevice != null) {
                    Log.i(LOG_TAG, "USB device detached: ${mUsbDevice!!.deviceName}")
                    Toast.makeText(context, "USB device has been turned off", Toast.LENGTH_LONG).show()
                    closeConnectionIfExists()
                    mHandler.obtainMessage(STATE_USB_NONE).sendToTarget()
                }
            } else if (UsbManager.ACTION_USB_DEVICE_ATTACHED == action) {
                Log.i(LOG_TAG, "USB device attached")
                // Handle device attachment if needed
            }
        }
    }

    fun init(reactContext: Context?) {
        Log.d("USBPrinterService", "init called")
        mContext = reactContext
        mUSBManager = mContext!!.getSystemService(Context.USB_SERVICE) as UsbManager
        mPermissionIndent = if (android.os.Build.VERSION.SDK_INT >= 31) {
            PendingIntent.getBroadcast(
                mContext,
                0,
                Intent(ACTION_USB_PERMISSION),
                PendingIntent.FLAG_MUTABLE
            )
        } else {
            PendingIntent.getBroadcast(
                mContext,
                0,
                Intent(ACTION_USB_PERMISSION),
                0
            )
        }
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        mContext!!.registerReceiver(mUsbDeviceReceiver, filter)
        Log.v(LOG_TAG, "ESC/POS Printer initialized")
    }

    fun closeConnectionIfExists() {
        Log.d("USBPrinterService", "executing closeConnectionIfExists")
        if (mUsbDeviceConnection != null) {
            mUsbDeviceConnection!!.releaseInterface(mUsbInterface)
            mUsbDeviceConnection!!.close()
            mUsbInterface = null
            mEndPoint = null
            mUsbDevice = null
            mUsbDeviceConnection = null
        }
    }

    val deviceList: List<UsbDevice>
        get() {
            if (mUSBManager == null) {
                Toast.makeText(mContext, "USB Manager is not initialized while trying to get devices list", Toast.LENGTH_LONG).show()
                return emptyList()
            }
            for (device in mUSBManager!!.deviceList.values) {
                Log.d("USBPrinterService", "Detected USB device: vendorId=${device.vendorId}, productId=${device.productId}")
            }
            return ArrayList(mUSBManager!!.deviceList.values)
        }

    fun selectDevice(vendorId: Int, productId: Int): Boolean {
        Log.v(LOG_TAG, "Request for device: vendor_id: $vendorId, product_id: $productId")
        if ((mUsbDevice == null) || (mUsbDevice!!.vendorId != vendorId) || (mUsbDevice!!.productId != productId)) {
            synchronized(printLock) {
                closeConnectionIfExists()
                val usbDevices: List<UsbDevice> = deviceList
                for (usbDevice: UsbDevice in usbDevices) {
                    if ((usbDevice.vendorId == vendorId) && (usbDevice.productId == productId)) {
                        Log.v(LOG_TAG, "Found matching device: vendor_id: ${usbDevice.vendorId}, product_id: ${usbDevice.productId}")
                        Log.v(LOG_TAG, "Has FEATURE_USB_HOST feature?: ${mContext!!.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)}")

//                        val permissionIntent = Intent(ACTION_USB_PERMISSION).apply {
//                            putExtra(USBManager.EXTRA_DEVICE, usbDevice) // Asegúrate de incluir el dispositivo USB
//                            putExtra(USBManager.EXTRA_PERMISSION_GRANTED, false) // El permiso será "false" inicialmente
//                        }
//
//                        mPermissionIndent = if (android.os.Build.VERSION.SDK_INT >= 31) {
//                            PendingIntent.getBroadcast(
//                                mContext,
//                                0,
//                                permissionIntent,
//                                PendingIntent.FLAG_UPDATE_CURRENT
//                            )
//                        } else {
//                            PendingIntent.getBroadcast(
//                                mContext,
//                                0,
//                                permissionIntent,
//                                0
//                            )
//                        }

                        mUSBManager!!.requestPermission(usbDevice, mPermissionIndent)
                        mHandler.obtainMessage(STATE_USB_CONNECTING).sendToTarget()
                        return true
                    }
                }
                Log.e(LOG_TAG, "No matching USB device found")
                return false
            }
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
            Log.i(LOG_TAG, "USB Connection already connected")
            return true
        }
        val usbInterface = mUsbDevice!!.getInterface(0)
        for (i in 0 until usbInterface.endpointCount) {
            val ep = usbInterface.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                if (ep.direction == UsbConstants.USB_DIR_OUT) {
                    val usbDeviceConnection = mUSBManager!!.openDevice(mUsbDevice)
                    if (usbDeviceConnection == null) {
                        Log.e(LOG_TAG, "Failed to open USB Connection")
                        return false
                    }
                    Toast.makeText(mContext, "Device connected", Toast.LENGTH_SHORT).show()
                    return if (usbDeviceConnection.claimInterface(usbInterface, true)) {
                        mEndPoint = ep
                        mUsbInterface = usbInterface
                        mUsbDeviceConnection = usbDeviceConnection
                        true
                    } else {
                        usbDeviceConnection.close()
                        Log.e(LOG_TAG, "Failed to claim USB interface")
                        false
                    }
                }
            }
        }
        Log.e(LOG_TAG, "No suitable endpoint found")
        return false
    }

    fun printText(text: String): Boolean {
        Log.v(LOG_TAG, "Printing text")
        val isConnected = openConnection()
        return if (isConnected) {
            Log.v(LOG_TAG, "Connected to device")
            Thread {
                synchronized(printLock) {
                    val bytes: ByteArray = text.toByteArray(Charset.forName("UTF-8"))
                    val b: Int = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, bytes, bytes.size, 100000)
                    Log.i(LOG_TAG, "Return code: $b")
                }
            }.start()
            true
        } else {
            Log.v(LOG_TAG, "Failed to connect to device")
            false
        }
    }

    fun printRawData(data: String): Boolean {
        Log.v(LOG_TAG, "Printing raw data: $data")
        val isConnected = openConnection()
        return if (isConnected) {
            Log.v(LOG_TAG, "Connected to device")
            Thread {
                synchronized(printLock) {
                    val bytes: ByteArray = Base64.decode(data, Base64.DEFAULT)
                    val b: Int = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, bytes, bytes.size, 100000)
                    Log.i(LOG_TAG, "Return code: $b")
                }
            }.start()
            true
        } else {
            Log.v(LOG_TAG, "Failed to connected to device")
            false
        }
    }

    fun printBytes(bytes: ArrayList<Int>): Boolean {
        Log.v(LOG_TAG, "Printing bytes")
        val isConnected = openConnection()
        if (isConnected) {
            val chunkSize = mEndPoint!!.maxPacketSize
            Log.v(LOG_TAG, "Max Packet Size: $chunkSize")
            Log.v(LOG_TAG, "Connected to device")
            Thread {
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
                    var b = 0
                    if (mUsbDeviceConnection != null) {
                        if (byteData.size > chunkSize) {
                            var chunks: Int = byteData.size / chunkSize
                            if (byteData.size % chunkSize > 0) {
                                ++chunks
                            }
                            for (i in 0 until chunks) {
//                                val buffer: ByteArray = byteData.copyOfRange(i * chunkSize, chunkSize + i * chunkSize)
                                val buffer: ByteArray = Arrays.copyOfRange(byteData, i * chunkSize, chunkSize + i * chunkSize)
                                b = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, buffer, chunkSize, 100000)
                            }
                        } else {
                            b = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, byteData, byteData.size, 100000)
                        }
                        Log.i(LOG_TAG, "Return code: $b")
                    }
                }
            }.start()
            return true
        } else {
            Log.v(LOG_TAG, "Failed to connected to device")
            return false
        }
    }

    companion object {
        @SuppressLint("StaticFieldLeak")
        private var mInstance: USBPrinterService? = null
        private const val LOG_TAG = "ESC POS Printer"
        private const val ACTION_USB_PERMISSION = "com.flutter_pos_printer.USB_PERMISSION"

        // Constants that indicate the current connection state
        const val STATE_USB_NONE = 0 // we're doing nothing
        const val STATE_USB_CONNECTING = 2 // now initiating an outgoing connection
        const val STATE_USB_CONNECTED = 3 // now connected to a remote device

        private val printLock = Any()

        fun getInstance(handler: Handler): USBPrinterService {
            Log.d("USBPrinterService", "getInstance called")
            if (mInstance == null) {
                mInstance = USBPrinterService(handler)
            }
            return mInstance!!
        }
    }
}