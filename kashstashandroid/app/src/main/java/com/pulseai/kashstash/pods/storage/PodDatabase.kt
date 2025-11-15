package com.pulseai.kashstash.pods.storage

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.pulseai.kashstash.pods.models.Digest
import com.pulseai.kashstash.pods.models.PodConfig
import com.pulseai.kashstash.pods.models.PodNode

@Database(
    entities = [PodConfig::class, PodNode::class, Digest::class],
    version = 1,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class PodDatabase : RoomDatabase() {
    abstract fun podDao(): PodDao

    companion object {
        @Volatile
        private var INSTANCE: PodDatabase? = null

        fun getDatabase(context: Context): PodDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    PodDatabase::class.java,
                    "pod_database"
                )
                    .fallbackToDestructiveMigration() // For development
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}