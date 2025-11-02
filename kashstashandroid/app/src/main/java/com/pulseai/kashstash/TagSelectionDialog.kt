package com.pulseai.kashstash

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.fragment.app.DialogFragment

class TagSelectionDialog(
    private val recentTags: List<RecentTag>,
    private val onTagsSelected: (String) -> Unit
) : DialogFragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.dialog_select_tags, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val tagInput = view.findViewById<EditText>(R.id.tagInput)
        val recentTagsList = view.findViewById<ListView>(R.id.recentTagsList)
        val submitButton = view.findViewById<Button>(R.id.submitButton)
        val cancelButton = view.findViewById<Button>(R.id.cancelButton)

        // Setup recent tags list
        val recentTagsDisplay = recentTags.take(10).mapIndexed { index, tag ->
            "${index + 1}. ${if (tag.value.length > 60) tag.value.take(57) + "..." else tag.value}"
        }

        val adapter = ArrayAdapter(requireContext(), android.R.layout.simple_list_item_1, recentTagsDisplay)
        recentTagsList.adapter = adapter

        recentTagsList.setOnItemClickListener { _, _, position, _ ->
            if (position < recentTags.size) {
                tagInput.setText(recentTags[position].value)
            }
        }

        submitButton.setOnClickListener {
            val tags = tagInput.text.toString().trim()
            onTagsSelected(tags)
            dismiss()
        }

        cancelButton.setOnClickListener {
            dismiss()
        }
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
    }
}