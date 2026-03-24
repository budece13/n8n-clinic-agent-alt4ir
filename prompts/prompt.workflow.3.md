Eres un experto en n8n y LangChain y debes construir un workflow de producción en 
formato JSON importable directamente en n8n (versión 1.x)(Impórtalo tú de manera autónoma en mi instancia de n8n con uso de mi api key disponible en .mcp.json). El workflow se llama 
"WA-Clinic-Info-RAG" y actúa como sub-workflow especializado en responder preguntas 
sobre información de la clínica: servicios, precios, horarios, FAQ, ubicación, etc.

## FUNCIÓN DE ESTE WORKFLOW
Es llamado como sub-workflow desde WA-Inbound-Orchestrator. Recibe una pregunta 
en lenguaje natural y devuelve una respuesta precisa y amigable basada en la 
información oficial de la clínica, sin alucinar datos.

## TRIGGER
Nodo: Execute Workflow Trigger
Recibe:
{
  "question": "string — la pregunta del usuario en lenguaje natural",
  "clinic_id": "string",
  "language": "es|en|ca (detectado automáticamente, default es)"
}

## NODOS Y LÓGICA

### Nodo 1: "Load Clinic Knowledge Base" (Postgres Node)
Query:
SELECT kb_type, content, metadata 
FROM clinic_knowledge_base 
WHERE clinic_id = $1 AND active = true
ORDER BY kb_type;

Devuelve registros de tipo: 'services', 'pricing', 'schedule', 'faq', 
'location', 'policies', 'team'

### Nodo 2: "Format Knowledge Context" (Code Node)
Procesa los registros y los formatea en un contexto estructurado:

const kb = items[0].json.rows;
const context = {
  services: kb.filter(r => r.kb_type === 'services').map(r => r.content).join('\n'),
  pricing: kb.filter(r => r.kb_type === 'pricing').map(r => r.content).join('\n'),
  schedule: kb.filter(r => r.kb_type === 'schedule').map(r => r.content).join('\n'),
  faq: kb.filter(r => r.kb_type === 'faq').map(r => r.content).join('\n'),
  location: kb.filter(r => r.kb_type === 'location').map(r => r.content).join('\n'),
  policies: kb.filter(r => r.kb_type === 'policies').map(r => r.content).join('\n'),
};
return [{ json: { context, question: items[0].json.question } }];

### Nodo 3: "Classify Question Intent" (Basic LLM Chain)
Prompt: 
"Clasifica la siguiente pregunta en una de estas categorías: 
 services | pricing | schedule | faq | location | policies | general
 Pregunta: {{question}}
 Responde SOLO con la categoría, sin más texto."

Esto permite priorizar el fragmento de contexto más relevante.

### Nodo 4: "Generate Answer" (Basic LLM Chain)
Modelo: gpt-4o-mini (suficiente para RAG sobre texto estructurado, más económico)
System Prompt:
"Eres el asistente virtual de {{clinic_name}}. Responde ÚNICAMENTE basándote en 
la información proporcionada en el contexto. Si la información no está disponible 
en el contexto, di exactamente: 'No tengo esa información disponible, te recomiendo 
contactar directamente con la clínica.'

NO inventes precios, horarios ni servicios. Sé conciso y amigable.
Responde siempre en el mismo idioma que la pregunta.

CONTEXTO DE LA CLÍNICA:
Servicios: {{context.services}}
Precios: {{context.pricing}}
Horarios: {{context.schedule}}
FAQ: {{context.faq}}
Ubicación: {{context.location}}
Políticas: {{context.policies}}

PREGUNTA DEL USUARIO: {{question}}"

User Prompt: "{{question}}"

### Nodo 5: "Validate Answer Quality" (Code Node)
Verifica que la respuesta no contenga frases de alucinación típica:
- Si contiene "según mis datos", "estimo que", "aproximadamente" 
  sin base en el contexto → reemplazar por mensaje de derivación a clínica
- Si la respuesta supera 500 caracteres → resumir con segundo LLM call

### Nodo 6: "Log Query" (Postgres Node)
INSERT INTO clinic_info_queries (
  clinic_id, question, intent_category, answer, created_at
) VALUES ($1, $2, $3, $4, NOW());

Esto permite analizar qué preguntan más los pacientes y mejorar el KB.

### Nodo 7: "Return Response" (Set Node)
Devuelve al orquestador:
{
  "success": true,
  "answer": "{{generated_answer}}",
  "intent": "{{classified_intent}}",
  "source": "knowledge_base"
}

## FALLBACK: SI KB ESTÁ VACÍO
Si la query al KB devuelve 0 registros:
→ Nodo "Default Response": devuelve mensaje pidiendo al usuario contactar 
  directamente con la clínica, e incluye el teléfono/email de la clínica 
  (desde tabla clinics).

## ESQUEMA DE BASE DE DATOS (incluir como comentario)
CREATE TABLE clinic_knowledge_base (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id VARCHAR(100) NOT NULL,
  kb_type VARCHAR(50) NOT NULL, -- services|pricing|schedule|faq|location|policies|team
  title VARCHAR(200),
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE clinic_info_queries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id VARCHAR(100),
  question TEXT,
  intent_category VARCHAR(50),
  answer TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Ejemplo de datos iniciales para testing:
INSERT INTO clinic_knowledge_base (clinic_id, kb_type, title, content) VALUES
('default', 'schedule', 'Horarios', 'Lunes a Viernes: 9:00 - 20:00. Sábados: 10:00 - 14:00. Domingos: Cerrado.'),
('default', 'pricing', 'Tarifas', 'Consulta general: 50€. Primera visita: 70€. Revisión: 40€.'),
('default', 'faq', 'Cancelaciones', 'Las cancelaciones deben realizarse con mínimo 24 horas de antelación.'),
('default', 'location', 'Ubicación', 'Calle Ejemplo 123, Madrid. Metro: Sol (líneas 1, 2, 3). Parking disponible.');

## NOTAS DE PRODUCCIÓN
- El modelo gpt-4o-mini es suficiente para este workflow y reduce costos 
  significativamente vs gpt-4o
- Implementar caché: si la misma pregunta (normalizada) fue respondida en las 
  últimas 6h para el mismo clinic_id, devolver respuesta cacheada sin llamar al LLM
  (tabla: clinic_info_cache con TTL)
- El KB debe poder actualizarse desde un workflow separado de administración 
  sin reiniciar nada

## OUTPUT ESPERADO
JSON completo importable en n8n con todos los nodos configurados, credentials 
referenciadas por nombre, y connections completas.