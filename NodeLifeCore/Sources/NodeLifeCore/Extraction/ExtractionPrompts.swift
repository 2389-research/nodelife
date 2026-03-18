// ABOUTME: Prompt templates for LLM-based entity, relationship, and theme extraction from meeting transcripts.
// ABOUTME: Builds structured system/user prompts that request JSON output conforming to defined schemas.

import Foundation

public struct ExtractionPrompt: Sendable {
    public let systemPrompt: String
    public let userMessage: String

    public init(systemPrompt: String, userMessage: String) {
        self.systemPrompt = systemPrompt
        self.userMessage = userMessage
    }
}

public enum ExtractionPrompts {

    // MARK: - Entity Extraction

    /// Builds a prompt that asks the LLM to extract entities from a meeting transcript.
    /// The system prompt instructs the model to return ONLY valid JSON matching the entity schema.
    public static func entityExtraction(
        meetingTitle: String,
        attendees: [String],
        transcriptText: String
    ) -> ExtractionPrompt {
        let systemPrompt = """
            You are an entity extraction assistant. Analyze meeting transcripts and extract named entities.

            Return ONLY valid JSON with no markdown formatting, no code fences, and no additional text.

            The JSON must conform to this schema:
            {
              "entities": [
                {
                  "name": "string",
                  "type": "person | organization | project | concept | topic | place | actionItem | blogIdea | idea | other",
                  "confidence": 0.0 to 1.0,
                  "mentions": [
                    {
                      "surface_form": "string",
                      "chunk_ordinal": 0
                    }
                  ]
                }
              ]
            }

            Rules:
            - "type" must be one of: person, organization, project, concept, topic, place, actionItem, blogIdea, idea, other
            - "confidence" is a float between 0.0 and 1.0 indicating extraction confidence
            - "mentions" is an array of surface forms and the chunk ordinal where each mention appears
            - Deduplicate entities that refer to the same thing
            - Do not include common words or filler as entities
            """

        let attendeeList = attendees.joined(separator: ", ")
        let userMessage = """
            Meeting title: \(meetingTitle)
            Attendees: \(attendeeList)

            Transcript:
            \(transcriptText)
            """

        return ExtractionPrompt(systemPrompt: systemPrompt, userMessage: userMessage)
    }

    // MARK: - Theme Extraction

    /// Builds a prompt that asks the LLM to extract themes from a meeting transcript.
    /// The system prompt instructs the model to return ONLY valid JSON matching the theme schema.
    public static func themeExtraction(
        meetingTitle: String,
        transcriptText: String
    ) -> ExtractionPrompt {
        let systemPrompt = """
            You are a theme extraction assistant. Analyze meeting transcripts and identify key themes discussed.

            Return ONLY valid JSON with no markdown formatting, no code fences, and no additional text.

            The JSON must conform to this schema:
            {
              "themes": [
                {
                  "label": "string",
                  "description": "string",
                  "confidence": 0.0 to 1.0,
                  "chunk_ordinals": [integer]
                }
              ]
            }

            Rules:
            - "label" is a short name for the theme
            - "description" is a one-sentence summary of the theme
            - "confidence" is a float between 0.0 and 1.0 indicating extraction confidence
            - "chunk_ordinals" lists the transcript chunk ordinals where this theme appears
            - Identify 3-10 themes per transcript
            """

        let userMessage = """
            Meeting title: \(meetingTitle)

            Transcript:
            \(transcriptText)
            """

        return ExtractionPrompt(systemPrompt: systemPrompt, userMessage: userMessage)
    }

    // MARK: - Relationship Extraction

    /// Builds a prompt that asks the LLM to extract relationships between known entities in a meeting transcript.
    /// The system prompt instructs the model to return ONLY valid JSON matching the relationship schema.
    public static func relationshipExtraction(
        meetingTitle: String,
        entities: [String],
        transcriptText: String
    ) -> ExtractionPrompt {
        let systemPrompt = """
            You are a relationship extraction system. Given a list of known entities and a meeting transcript, \
            identify relationships between the entities.

            Return a JSON object with this exact schema:
            {
              "relationships": [
                {
                  "from_entity": "string - exact name from the entity list",
                  "to_entity": "string - exact name from the entity list",
                  "type": "worksFor | worksOn | manages | collaborates | mentions | cooccurs | discusses | relatesTo | owns | inspiredBy | partOf | reports",
                  "confidence": 0.0-1.0,
                  "evidence_chunk_ordinals": [integer]
                }
              ]
            }

            Rules:
            - Only use entity names from the provided list.
            - Relationship types: worksFor (person->org), worksOn (person->project), manages (person->person/project), \
            collaborates (person<->person), mentions (entity->entity), cooccurs (entities in same context), \
            discusses (person->topic/concept), relatesTo (general), owns (person/org->project), \
            inspiredBy (idea->entity), partOf (sub->parent), reports (person->person).
            - evidence_chunk_ordinals lists transcript segments that support this relationship.
            - Confidence should reflect how strongly the transcript supports this relationship.
            - Return ONLY valid JSON. No markdown, no explanation.
            """

        var userParts: [String] = []
        userParts.append("Meeting title: \(meetingTitle)")
        userParts.append("")
        userParts.append("Known entities:")
        for entity in entities {
            userParts.append("- \(entity)")
        }
        userParts.append("")
        userParts.append("Transcript segments (one per line, numbered):")
        userParts.append(transcriptText)

        return ExtractionPrompt(
            systemPrompt: systemPrompt,
            userMessage: userParts.joined(separator: "\n")
        )
    }

    // MARK: - Transcript Formatting

    /// Formats meeting chunks for inclusion in extraction prompts.
    /// Each line is formatted as "[chunkIndex] [speaker] text", using normalizedText when available.
    public static func formatTranscriptForExtraction(chunks: [MeetingChunk]) -> String {
        chunks.map { chunk in
            let text = chunk.normalizedText ?? chunk.text
            let speakerTag = chunk.speaker.map { "[\($0)] " } ?? ""
            return "[\(chunk.chunkIndex)] \(speakerTag)\(text)"
        }.joined(separator: "\n")
    }
}
