package com.llfbandit.record.record.model

/** Why a take ended. Dart reads the [id]. */
enum class StopReason(val id: String) {
  /** The app ended it: stop(), cancel(), dispose(), or a new start(). */
  STOP("stop"),
  ROUTE_CHANGE("routeChange"),
  INTERRUPTION("interruption"),
  ERROR("error"),
}

/** The end of a take. [path] is null after cancel(), and for a stream. */
data class RecordStop(val reason: StopReason, val path: String?, val error: String? = null) {
  // Dart reads the state from it too.
  fun toMap(): Map<String, Any?> = mapOf(
    "state" to RecordState.STOP.id,
    "reason" to reason.id,
    "path" to path,
    "error" to error,
  )
}
