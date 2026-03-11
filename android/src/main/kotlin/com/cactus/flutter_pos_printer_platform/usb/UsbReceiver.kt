package com.cactus.flutter_pos_printer_platform.usb

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.util.Log

class UsbReceiver(private val manager: UsbPrinterManager? = null) : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        Log.d("UsbReceiver", "Inside USB Broadcast action $action")

        val usbDevice: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        if (usbDevice == null) return

        when (action) {
            UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                Log.d("UsbReceiver", "USB Device attached: ${usbDevice.deviceName}")
                manager?.onUsbAttached(usbDevice)

                val intentPermission = Intent("com.flutter_pos_printer.USB_PERMISSION")
                intentPermission.setPackage(context?.packageName)
                val mPermissionIndent = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    PendingIntent.getBroadcast(context, 0, intentPermission, PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                } else {
                    PendingIntent.getBroadcast(context, 0, intentPermission, PendingIntent.FLAG_UPDATE_CURRENT)
                }
                val mUSBManager = context?.getSystemService(Context.USB_SERVICE) as UsbManager?
                mUSBManager?.requestPermission(usbDevice, mPermissionIndent)
            }

            UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                Log.d("UsbReceiver", "USB Device detached: ${usbDevice.deviceName}")
                manager?.onUsbDetached(usbDevice)
            }

            "com.flutter_pos_printer.USB_PERMISSION" -> {
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                Log.d("UsbReceiver", "USB Permission result: $granted for ${usbDevice.deviceName}")
                UsbPermissionManager.handlePermissionResult(usbDevice.deviceName, granted)
            }
        }
    }
}

