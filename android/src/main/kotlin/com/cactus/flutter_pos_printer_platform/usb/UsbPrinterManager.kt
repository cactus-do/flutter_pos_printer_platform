package com.cactus.flutter_pos_printer_platform.usb

import android.content.Context
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Handler
import android.util.Log
import java.util.concurrent.ConcurrentHashMap


class UsbPrinterManager(
    private val context: Context,
    private val eventHandler: Handler
) {

    private val printers = ConcurrentHashMap<String, UsbPrinter>() // deviceId → printer
    private val usbManager: UsbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

    fun listDevices(): List<UsbDevice> {
        return usbManager.deviceList.values.toList()
    }

    fun isConnected(address: String): Boolean = printers[address]?.isConnected() ?: false

    fun connect(address: String): Boolean {
        Log.d("UsbPrinterManager", "Connecting to address: $address")
        if (printers.containsKey(address)) {
            Log.d("UsbPrinterManager", "Printer already in map for $address")
            // We should still check if it's connected
            val p = printers[address]
            if (p != null) {
                return p.connect()
            }
        }

        val device = usbManager.deviceList[address] ?: run {
            Log.e("UsbPrinterManager", "Device not found for address: $address")
            return false
        }
        val printer = UsbPrinter(context, device, eventHandler)
        val success = printer.connect()
        if (success) {
            Log.d("UsbPrinterManager", "Connection success, adding to map: $address")
            printers[address] = printer
        } else {
            Log.e("UsbPrinterManager", "Connection failed for address: $address")
        }
        return success
    }



    fun disconnect(address: String) {
        printers.remove(address)?.close()
    }

    fun printText(address: String, text: String): Boolean =
        printers[address]?.printText(text) ?: false

    fun printRaw(address: String, base64: String): Boolean =
        printers[address]?.printRaw(base64) ?: false

    fun printBytes(address: String, bytes: ArrayList<Int>): Boolean =
        printers[address]?.printBytes(bytes) ?: false

    fun onUsbDetached(device: UsbDevice) {
        disconnect(device.deviceName)
    }

    fun closeAll() {
        printers.values.forEach { it.close() }
        printers.clear()
    }

}