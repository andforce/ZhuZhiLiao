package com.azhegezhege.zhuzhiliao.ui

import com.azhegezhege.zhuzhiliao.network.LeaderboardEntry
import com.azhegezhege.zhuzhiliao.network.LeaderboardSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LeaderboardPresentationTest {
    @Test
    fun `keeps a player outside the leading entries in a separate section`() {
        val leader = LeaderboardEntry(code = "LEADER", score = 6_888, rank = 1)
        val me = LeaderboardEntry(code = "MYCODE", score = 131, rank = 217)

        val sections = LeaderboardPresentation.sections(
            LeaderboardSnapshot(
                totalPlayers = 617,
                entries = listOf(leader),
                me = me,
            ),
        )

        assertEquals(listOf(leader), sections.leadingEntries)
        assertEquals(me, sections.separateMe)
    }

    @Test
    fun `does not duplicate me and formats scores with grouping separators`() {
        val me = LeaderboardEntry(code = "MYCODE", score = 5_225, rank = 3)

        val sections = LeaderboardPresentation.sections(
            LeaderboardSnapshot(
                totalPlayers = 3,
                entries = listOf(me),
                me = me,
            ),
        )

        assertNull(sections.separateMe)
        assertEquals("5,225", LeaderboardPresentation.formattedScore(me.score))
    }
}
