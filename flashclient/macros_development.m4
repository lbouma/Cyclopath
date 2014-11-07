m4_dnl Copyright (c) 2006-2013 Regents of the University of Minnesota.
m4_dnl For licensing terms, see the file LICENSE.
m4_dnl
m4_dnl There are two m4 files: one for production builds, and another for 
m4_dnl development builds. The latter contains all the Flash trace messages.
m4_dnl
m4_dnl WARNING: DO NOT EDIT macros.m4 - it's not checked into the repository 
m4_dnl                                  and it gets overwritten by make.
m4_dnl
m4_dnl == M4 Caveats ==
m4_dnl
m4_dnl Commas inside 'quoted' "things" are still seen by m4, so
m4_dnl    m4_DEBUG('My string, your string');
m4_dnl prints as
m4_dnl    My string  your string
m4_dnl (note the double space).
m4_dnl
m4_dnl == Runtime Asserts ==
m4_dnl
m4_define(`m4_ASSERT', `G.assert($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSURT', `G.assert($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSERT_EXISTS', `G.assert($1 !== null, "m4___file__:m4___line__")')m4_dnl
m4_dnl m4_define(`m4_ASSERT_FALSE', `G.assert(false, "m4___file__:m4___line__")')m4_dnl
m4_dnl
m4_dnl == Specialized Macros ==
m4_dnl
m4_define(`m4_ASSERT_ELSE', `else { G.assert(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_ASSERT_SOFT', `G.assert_soft($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSERT_ELSE_SOFT', `else { G.assert_soft(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_ASSERT_KNOWN', `G.assert_known($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSERT_ELSE_KNOWN', `else { G.assert_known(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_SERVED', `G.assert_soft($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ELSE_SERVED', `else { G.assert_soft(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_DEBUG_CLLL', `G.log_clll.debug($*)')m4_dnl
m4_define(`m4_DEBUG_TIME', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}')m4_dnl
m4_dnl
m4_dnl == Kludgy Trace Macros ==
m4_dnl
m4_dnl The following is a big mess because... well, that's the way m4_IT_IS.
m4_dnl If your macro contains newlines, m4 removes them. Which means,
m4_dnl the flex compiler incorrectly reports line numbers, because the 
m4_dnl files in flashclient/build/ are shorter than the source files. 
m4_dnl (Is "shorter" a proper computer sciency term?) So herein, we 
m4_dnl deliberately add newlines to the macros. Use the suffix 2 through 9 on 
m4_dnl m4_ASSERT, m4_DEBUG, and everyone's favorite, m4_VERBOSE.
m4_dnl
m4_dnl Pre-2013.05.22: Is there a way to automate the following, or is this
m4_dnl                 file forever ugly?
m4_dnl Post-2013.05.22: See scripts/dev/flashclient_macros-make.py.
m4_dnl
m4_dnl NOTE: We don't need to kludge m4_ASSERT (e.g., m4_ASSERT2) because 
m4_dnl       assert statements do not contain commas, which is what causes 
m4_dnl       m4 to whack our newlines -- however, we do need to kludge at least
m4_dnl       one m4_ASSERT (e.g., m4_ASSERT2), for asserts that start with an  
m4_dnl       open parentheses followed by a newline, since m4 whacks the CR.
m4_define(`m4_ASSERT2', `G.assert($1, "m4___file__:m4___line__")'
)m4_dnl
m4_dnl 
m4_define(`m4_VERBOSE', `log.verbose($*)')m4_dnl
m4_define(`m4_VERBOSE2', `log.verbose($*)'
)m4_dnl
m4_define(`m4_VERBOSE3', `log.verbose($*)'

)m4_dnl
m4_define(`m4_VERBOSE4', `log.verbose($*)'


)m4_dnl
m4_define(`m4_VERBOSE5', `log.verbose($*)'



)m4_dnl
m4_define(`m4_VERBOSE6', `log.verbose($*)'




)m4_dnl
m4_define(`m4_VERBOSE7', `log.verbose($*)'





)m4_dnl
m4_define(`m4_VERBOSE8', `log.verbose($*)'






)m4_dnl
m4_define(`m4_VERBOSE9', `log.verbose($*)'







)m4_dnl
m4_define(`m4_TALKY', `log.talky($*)')m4_dnl
m4_define(`m4_TALKY2', `log.talky($*)'
)m4_dnl
m4_define(`m4_TALKY3', `log.talky($*)'

)m4_dnl
m4_define(`m4_TALKY4', `log.talky($*)'


)m4_dnl
m4_define(`m4_TALKY5', `log.talky($*)'



)m4_dnl
m4_define(`m4_TALKY6', `log.talky($*)'




)m4_dnl
m4_define(`m4_TALKY7', `log.talky($*)'





)m4_dnl
m4_define(`m4_TALKY8', `log.talky($*)'






)m4_dnl
m4_define(`m4_TALKY9', `log.talky($*)'







)m4_dnl
m4_define(`m4_DEBUG', `log.debug($*)')m4_dnl
m4_define(`m4_DEBUG2', `log.debug($*)'
)m4_dnl
m4_define(`m4_DEBUG3', `log.debug($*)'

)m4_dnl
m4_define(`m4_DEBUG4', `log.debug($*)'


)m4_dnl
m4_define(`m4_DEBUG5', `log.debug($*)'



)m4_dnl
m4_define(`m4_DEBUG6', `log.debug($*)'




)m4_dnl
m4_define(`m4_DEBUG7', `log.debug($*)'





)m4_dnl
m4_define(`m4_DEBUG8', `log.debug($*)'






)m4_dnl
m4_define(`m4_DEBUG9', `log.debug($*)'







)m4_dnl
m4_define(`m4_INFO', `log.info($*)')m4_dnl
m4_define(`m4_INFO2', `log.info($*)'
)m4_dnl
m4_define(`m4_INFO3', `log.info($*)'

)m4_dnl
m4_define(`m4_INFO4', `log.info($*)'


)m4_dnl
m4_define(`m4_INFO5', `log.info($*)'



)m4_dnl
m4_define(`m4_INFO6', `log.info($*)'




)m4_dnl
m4_define(`m4_INFO7', `log.info($*)'





)m4_dnl
m4_define(`m4_INFO8', `log.info($*)'






)m4_dnl
m4_define(`m4_INFO9', `log.info($*)'







)m4_dnl
m4_define(`m4_WARNING', `log.warning($*)')m4_dnl
m4_define(`m4_WARNING2', `log.warning($*)'
)m4_dnl
m4_define(`m4_WARNING3', `log.warning($*)'

)m4_dnl
m4_define(`m4_WARNING4', `log.warning($*)'


)m4_dnl
m4_define(`m4_WARNING5', `log.warning($*)'



)m4_dnl
m4_define(`m4_WARNING6', `log.warning($*)'




)m4_dnl
m4_define(`m4_WARNING7', `log.warning($*)'





)m4_dnl
m4_define(`m4_WARNING8', `log.warning($*)'






)m4_dnl
m4_define(`m4_WARNING9', `log.warning($*)'







)m4_dnl
m4_define(`m4_ERROR', `log.error($*)')m4_dnl
m4_define(`m4_ERROR2', `log.error($*)'
)m4_dnl
m4_define(`m4_ERROR3', `log.error($*)'

)m4_dnl
m4_define(`m4_ERROR4', `log.error($*)'


)m4_dnl
m4_define(`m4_ERROR5', `log.error($*)'



)m4_dnl
m4_define(`m4_ERROR6', `log.error($*)'




)m4_dnl
m4_define(`m4_ERROR7', `log.error($*)'





)m4_dnl
m4_define(`m4_ERROR8', `log.error($*)'






)m4_dnl
m4_define(`m4_ERROR9', `log.error($*)'







)m4_dnl
m4_define(`m4_CRITICAL', `log.critical($*)')m4_dnl
m4_define(`m4_CRITICAL2', `log.critical($*)'
)m4_dnl
m4_define(`m4_CRITICAL3', `log.critical($*)'

)m4_dnl
m4_define(`m4_CRITICAL4', `log.critical($*)'


)m4_dnl
m4_define(`m4_CRITICAL5', `log.critical($*)'



)m4_dnl
m4_define(`m4_CRITICAL6', `log.critical($*)'




)m4_dnl
m4_define(`m4_CRITICAL7', `log.critical($*)'





)m4_dnl
m4_define(`m4_CRITICAL8', `log.critical($*)'






)m4_dnl
m4_define(`m4_CRITICAL9', `log.critical($*)'







)m4_dnl
m4_define(`m4_EXCEPTION', `log.error($*)')m4_dnl
m4_define(`m4_EXCEPTION2', `log.error($*)'
)m4_dnl
m4_define(`m4_EXCEPTION3', `log.error($*)'

)m4_dnl
m4_define(`m4_EXCEPTION4', `log.error($*)'


)m4_dnl
m4_define(`m4_EXCEPTION5', `log.error($*)'



)m4_dnl
m4_define(`m4_EXCEPTION6', `log.error($*)'




)m4_dnl
m4_define(`m4_EXCEPTION7', `log.error($*)'





)m4_dnl
m4_define(`m4_EXCEPTION8', `log.error($*)'






)m4_dnl
m4_define(`m4_EXCEPTION9', `log.error($*)'







)m4_dnl
m4_define(`m4_DEBUG_CLLL', `if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { G.log_clll.debug($*);}')m4_dnl
m4_define(`m4_DEBUG_CLLL2', `if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { G.log_clll.debug($*);}'
)m4_dnl
m4_define(`m4_DEBUG_CLLL3', `if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { G.log_clll.debug($*);}'

)m4_dnl
m4_define(`m4_DEBUG_CLLL4', `if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { G.log_clll.debug($*);}'


)m4_dnl
m4_define(`m4_DEBUG_CLLL5', `if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { G.log_clll.debug($*);}'



)m4_dnl
m4_define(`m4_DEBUG_CLLL6', `if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { G.log_clll.debug($*);}'




)m4_dnl
m4_define(`m4_DEBUG_CLLL7', `if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { G.log_clll.debug($*);}'





)m4_dnl
m4_define(`m4_DEBUG_CLLL8', `if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { G.log_clll.debug($*);}'






)m4_dnl
m4_define(`m4_DEBUG_CLLL9', `if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { G.log_clll.debug($*);}'







)m4_dnl
m4_define(`m4_DEBUG_TIME', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}')m4_dnl
m4_define(`m4_DEBUG_TIME2', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}'
)m4_dnl
m4_define(`m4_DEBUG_TIME3', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}'

)m4_dnl
m4_define(`m4_DEBUG_TIME4', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}'


)m4_dnl
m4_define(`m4_DEBUG_TIME5', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}'



)m4_dnl
m4_define(`m4_DEBUG_TIME6', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}'




)m4_dnl
m4_define(`m4_DEBUG_TIME7', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}'





)m4_dnl
m4_define(`m4_DEBUG_TIME8', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}'






)m4_dnl
m4_define(`m4_DEBUG_TIME9', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}'







)m4_dnl
m4_define(`m4_PPUSH', `if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { log.debug($*);}')m4_dnl
m4_define(`m4_PPUSH2', `if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { log.debug($*);}'
)m4_dnl
m4_define(`m4_PPUSH3', `if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { log.debug($*);}'

)m4_dnl
m4_define(`m4_PPUSH4', `if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { log.debug($*);}'


)m4_dnl
m4_define(`m4_PPUSH5', `if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { log.debug($*);}'



)m4_dnl
m4_define(`m4_PPUSH6', `if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { log.debug($*);}'




)m4_dnl
m4_define(`m4_PPUSH7', `if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { log.debug($*);}'





)m4_dnl
m4_define(`m4_PPUSH8', `if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { log.debug($*);}'






)m4_dnl
m4_define(`m4_PPUSH9', `if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { log.debug($*);}'







)m4_dnl
m4_dnl
