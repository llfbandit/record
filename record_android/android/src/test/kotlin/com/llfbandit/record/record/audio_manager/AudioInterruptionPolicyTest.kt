package com.llfbandit.record.record.audio_manager

import com.llfbandit.record.record.model.AudioInterruption
import com.llfbandit.record.testRecordConfig
import org.junit.Assert.assertEquals
import org.junit.Test

class AudioInterruptionPolicyTest {
  private fun react(mode: AudioInterruption, event: EnvironmentEvent) =
    AudioInterruptionPolicy.react(
      testRecordConfig(audioInterruption = mode.ordinal),
      event,
    )

  @Test
  fun `none ignores focus loss and regain`() {
    assertEquals(emptyList<PolicyAction>(), react(AudioInterruption.NONE, EnvironmentEvent.FocusLost))
    assertEquals(emptyList<PolicyAction>(), react(AudioInterruption.NONE, EnvironmentEvent.FocusRegained))
  }

  @Test
  fun `pause pauses on focus loss but does not auto-resume`() {
    assertEquals(listOf(PolicyAction.Pause), react(AudioInterruption.PAUSE, EnvironmentEvent.FocusLost))
    assertEquals(emptyList<PolicyAction>(), react(AudioInterruption.PAUSE, EnvironmentEvent.FocusRegained))
  }

  @Test
  fun `pauseResume pauses on loss and resumes on regain`() {
    assertEquals(
      listOf(PolicyAction.Pause),
      react(AudioInterruption.PAUSE_RESUME, EnvironmentEvent.FocusLost),
    )
    assertEquals(
      listOf(PolicyAction.Resume),
      react(AudioInterruption.PAUSE_RESUME, EnvironmentEvent.FocusRegained),
    )
  }

  @Test
  fun `regain still yields resume right after a loss (no stale state check)`() {
    val config = testRecordConfig(audioInterruption = AudioInterruption.PAUSE_RESUME.ordinal)
    // A fast loss/regain cycle: the policy is stateless, so each call stands alone.
    assertEquals(listOf(PolicyAction.Pause), AudioInterruptionPolicy.react(config, EnvironmentEvent.FocusLost))
    assertEquals(listOf(PolicyAction.Resume), AudioInterruptionPolicy.react(config, EnvironmentEvent.FocusRegained))
  }
}
