package com.llfbandit.record.permission

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.pm.PackageManager
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class PermissionManagerTest {
  private val app = ApplicationProvider.getApplicationContext<Application>()
  private val manager = PermissionManager(app)

  @Test
  fun `a check without an activity reads the app permission`() {
    shadowOf(app).grantPermissions(Manifest.permission.RECORD_AUDIO)

    var granted: Boolean? = null
    manager.hasPermission(request = false) { granted = it }

    assertEquals(true, granted)
  }

  @Test
  fun `overlapping requests are all answered by the one dialog`() {
    shadowOf(app).denyPermissions(Manifest.permission.RECORD_AUDIO)
    manager.setActivity(Robolectric.buildActivity(Activity::class.java).setup().get())

    val answers = mutableListOf<Boolean>()
    manager.hasPermission { answers += it }
    manager.hasPermission { answers += it }
    assertTrue("both wait on the dialog", answers.isEmpty())

    manager.onRequestPermissionsResult(
      PermissionManager.RECORD_AUDIO_REQUEST_CODE,
      arrayOf(Manifest.permission.RECORD_AUDIO),
      intArrayOf(PackageManager.PERMISSION_GRANTED),
    )

    assertEquals(listOf(true, true), answers)
  }

  @Test
  fun `another plugin's result on our request code is left alone`() {
    shadowOf(app).denyPermissions(Manifest.permission.RECORD_AUDIO)
    manager.setActivity(Robolectric.buildActivity(Activity::class.java).setup().get())
    val answers = mutableListOf<Boolean>()
    manager.hasPermission { answers += it }

    val handled = manager.onRequestPermissionsResult(
      PermissionManager.RECORD_AUDIO_REQUEST_CODE,
      arrayOf(Manifest.permission.CAMERA),
      intArrayOf(PackageManager.PERMISSION_GRANTED),
    )

    assertFalse(handled)
    assertTrue("still waiting on our dialog", answers.isEmpty())
  }

  @Test
  fun `an interrupted request answers denied`() {
    shadowOf(app).denyPermissions(Manifest.permission.RECORD_AUDIO)
    manager.setActivity(Robolectric.buildActivity(Activity::class.java).setup().get())
    val answers = mutableListOf<Boolean>()
    manager.hasPermission { answers += it }

    manager.onRequestPermissionsResult(PermissionManager.RECORD_AUDIO_REQUEST_CODE, arrayOf(), intArrayOf())

    assertEquals(listOf(false), answers)
  }

  @Test
  fun `a result with nothing waiting is not ours`() {
    val handled = manager.onRequestPermissionsResult(
      PermissionManager.RECORD_AUDIO_REQUEST_CODE,
      arrayOf(Manifest.permission.RECORD_AUDIO),
      intArrayOf(PackageManager.PERMISSION_GRANTED),
    )

    assertFalse(handled)
  }

  @Test
  fun `callers left by a gone activity are answered, and the next call asks again`() {
    shadowOf(app).denyPermissions(Manifest.permission.RECORD_AUDIO)
    manager.setActivity(Robolectric.buildActivity(Activity::class.java).setup().get())
    val answers = mutableListOf<Boolean>()
    manager.hasPermission { answers += it }

    manager.setActivity(null)
    manager.answerPending()
    assertEquals(listOf(false), answers)

    val next = Robolectric.buildActivity(Activity::class.java).setup().get()
    manager.setActivity(next)
    manager.hasPermission { answers += it }
    assertEquals(
      "a new dialog is requested",
      Manifest.permission.RECORD_AUDIO,
      shadowOf(next).lastRequestedPermission?.requestedPermissions?.single(),
    )
  }
}
