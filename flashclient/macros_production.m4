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
m4_dnl FIXME [aa] Removes ASSERTs for release builds? Or is that a Bad Idea?
m4_dnl            (We still need to stop control flow, i.e., if we assert that
m4_dnl            something is not null but it is, we have no choice but to
m4_dnl            assert. So maybe the answer is a global try/catch block?)
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
m4_define(`m4_DEBUG_CLLL', `')m4_dnl
m4_define(`m4_DEBUG_TIME', `')m4_dnl
m4_dnl
m4_dnl == Kludgy Trace Macros ==
m4_dnl
m4_dnl See macros_development.m4 for the reason why the following is such a big
m4_dnl mess.
m4_dnl
m4_define(`m4_ASSERT2', `G.assert($1, "m4___file__:m4___line__")'
)m4_dnl
m4_dnl
m4_define(`m4_VERBOSE', `')m4_dnl
m4_define(`m4_VERBOSE2', `'
)m4_dnl
m4_define(`m4_VERBOSE3', `'

)m4_dnl
m4_define(`m4_VERBOSE4', `'


)m4_dnl
m4_define(`m4_VERBOSE5', `'



)m4_dnl
m4_define(`m4_VERBOSE6', `'




)m4_dnl
m4_define(`m4_VERBOSE7', `'





)m4_dnl
m4_define(`m4_VERBOSE8', `'






)m4_dnl
m4_define(`m4_VERBOSE9', `'







)m4_dnl
m4_define(`m4_TALKY', `')m4_dnl
m4_define(`m4_TALKY2', `'
)m4_dnl
m4_define(`m4_TALKY3', `'

)m4_dnl
m4_define(`m4_TALKY4', `'


)m4_dnl
m4_define(`m4_TALKY5', `'



)m4_dnl
m4_define(`m4_TALKY6', `'




)m4_dnl
m4_define(`m4_TALKY7', `'





)m4_dnl
m4_define(`m4_TALKY8', `'






)m4_dnl
m4_define(`m4_TALKY9', `'







)m4_dnl
m4_define(`m4_DEBUG', `')m4_dnl
m4_define(`m4_DEBUG2', `'
)m4_dnl
m4_define(`m4_DEBUG3', `'

)m4_dnl
m4_define(`m4_DEBUG4', `'


)m4_dnl
m4_define(`m4_DEBUG5', `'



)m4_dnl
m4_define(`m4_DEBUG6', `'




)m4_dnl
m4_define(`m4_DEBUG7', `'





)m4_dnl
m4_define(`m4_DEBUG8', `'






)m4_dnl
m4_define(`m4_DEBUG9', `'







)m4_dnl
m4_define(`m4_INFO', `')m4_dnl
m4_define(`m4_INFO2', `'
)m4_dnl
m4_define(`m4_INFO3', `'

)m4_dnl
m4_define(`m4_INFO4', `'


)m4_dnl
m4_define(`m4_INFO5', `'



)m4_dnl
m4_define(`m4_INFO6', `'




)m4_dnl
m4_define(`m4_INFO7', `'





)m4_dnl
m4_define(`m4_INFO8', `'






)m4_dnl
m4_define(`m4_INFO9', `'







)m4_dnl
m4_define(`m4_WARNING', `')m4_dnl
m4_define(`m4_WARNING2', `'
)m4_dnl
m4_define(`m4_WARNING3', `'

)m4_dnl
m4_define(`m4_WARNING4', `'


)m4_dnl
m4_define(`m4_WARNING5', `'



)m4_dnl
m4_define(`m4_WARNING6', `'




)m4_dnl
m4_define(`m4_WARNING7', `'





)m4_dnl
m4_define(`m4_WARNING8', `'






)m4_dnl
m4_define(`m4_WARNING9', `'







)m4_dnl
m4_define(`m4_ERROR', `')m4_dnl
m4_define(`m4_ERROR2', `'
)m4_dnl
m4_define(`m4_ERROR3', `'

)m4_dnl
m4_define(`m4_ERROR4', `'


)m4_dnl
m4_define(`m4_ERROR5', `'



)m4_dnl
m4_define(`m4_ERROR6', `'




)m4_dnl
m4_define(`m4_ERROR7', `'





)m4_dnl
m4_define(`m4_ERROR8', `'






)m4_dnl
m4_define(`m4_ERROR9', `'







)m4_dnl
m4_define(`m4_CRITICAL', `')m4_dnl
m4_define(`m4_CRITICAL2', `'
)m4_dnl
m4_define(`m4_CRITICAL3', `'

)m4_dnl
m4_define(`m4_CRITICAL4', `'


)m4_dnl
m4_define(`m4_CRITICAL5', `'



)m4_dnl
m4_define(`m4_CRITICAL6', `'




)m4_dnl
m4_define(`m4_CRITICAL7', `'





)m4_dnl
m4_define(`m4_CRITICAL8', `'






)m4_dnl
m4_define(`m4_CRITICAL9', `'







)m4_dnl
m4_define(`m4_EXCEPTION', `')m4_dnl
m4_define(`m4_EXCEPTION2', `'
)m4_dnl
m4_define(`m4_EXCEPTION3', `'

)m4_dnl
m4_define(`m4_EXCEPTION4', `'


)m4_dnl
m4_define(`m4_EXCEPTION5', `'



)m4_dnl
m4_define(`m4_EXCEPTION6', `'




)m4_dnl
m4_define(`m4_EXCEPTION7', `'





)m4_dnl
m4_define(`m4_EXCEPTION8', `'






)m4_dnl
m4_define(`m4_EXCEPTION9', `'







)m4_dnl
m4_define(`m4_DEBUG_CLLL', `')m4_dnl
m4_define(`m4_DEBUG_CLLL2', `'
)m4_dnl
m4_define(`m4_DEBUG_CLLL3', `'

)m4_dnl
m4_define(`m4_DEBUG_CLLL4', `'


)m4_dnl
m4_define(`m4_DEBUG_CLLL5', `'



)m4_dnl
m4_define(`m4_DEBUG_CLLL6', `'




)m4_dnl
m4_define(`m4_DEBUG_CLLL7', `'





)m4_dnl
m4_define(`m4_DEBUG_CLLL8', `'






)m4_dnl
m4_define(`m4_DEBUG_CLLL9', `'







)m4_dnl
m4_define(`m4_DEBUG_TIME', `')m4_dnl
m4_define(`m4_DEBUG_TIME2', `'
)m4_dnl
m4_define(`m4_DEBUG_TIME3', `'

)m4_dnl
m4_define(`m4_DEBUG_TIME4', `'


)m4_dnl
m4_define(`m4_DEBUG_TIME5', `'



)m4_dnl
m4_define(`m4_DEBUG_TIME6', `'




)m4_dnl
m4_define(`m4_DEBUG_TIME7', `'





)m4_dnl
m4_define(`m4_DEBUG_TIME8', `'






)m4_dnl
m4_define(`m4_DEBUG_TIME9', `'







)m4_dnl
m4_define(`m4_PPUSH', `')m4_dnl
m4_define(`m4_PPUSH2', `'
)m4_dnl
m4_define(`m4_PPUSH3', `'

)m4_dnl
m4_define(`m4_PPUSH4', `'


)m4_dnl
m4_define(`m4_PPUSH5', `'



)m4_dnl
m4_define(`m4_PPUSH6', `'




)m4_dnl
m4_define(`m4_PPUSH7', `'





)m4_dnl
m4_define(`m4_PPUSH8', `'






)m4_dnl
m4_define(`m4_PPUSH9', `'







)m4_dnl
m4_dnl
