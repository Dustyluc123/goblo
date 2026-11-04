-- Fase 4.2 (ADR 0053): a cabeça volta a ser uma peça só (rosto + cabelo originais). Quem
-- salvou cabelo, cor do cabelo, penteado extra ou o quepe passa a usar a cabeça original
-- correspondente:
-- - com o quepe (acessório cap-male-c): a cabeça male-c, que tem o quepe;
-- - com o cabelo de outra cabeça: a cabeça de onde o cabelo veio (o que mais se vê);
-- - senão, a cabeça que já estava escolhida.
-- Os campos hair, hairstyle e haircut saem do visual.
UPDATE player_body
SET data = json_remove(
    json_set(data,
        '$.look.head', CASE
            WHEN json_extract(data, '$.look.accessory') = 'cap-male-c' THEN 'male-c'
            WHEN json_extract(data, '$.look.haircut') IN ('female-a', 'female-b', 'female-c', 'female-d',
                'female-e', 'female-f', 'male-a', 'male-b', 'male-c', 'male-d', 'male-e', 'male-f')
                THEN json_extract(data, '$.look.haircut')
            ELSE COALESCE(json_extract(data, '$.look.head'), '')
        END,
        '$.look.accessory', CASE
            WHEN json_extract(data, '$.look.accessory') IN ('aid-glasses', 'aid-sunglasses')
                THEN json_extract(data, '$.look.accessory')
            ELSE 'none'
        END),
    '$.look.hair', '$.look.hairstyle', '$.look.haircut')
WHERE json_type(data, '$.look') = 'object' AND COALESCE(json_extract(data, '$.look.head'), '') != '';
