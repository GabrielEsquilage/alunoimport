import csv
import random
import os

nomes = [
    "Marcon", "Ana", "Lucas", "Julia", "Roberto", "Patrícia", "Carlos", "Beatriz",
    "Guilherme", "Letícia", "Ricardo", "Fernanda", "Gustavo", "Camila", "Felipe", "Amanda",
    "Thiago", "Larissa", "Vinícius", "Bianca", "Leonardo", "Carolina", "Rodrigo", "Gabriela",
    "Eduardo", "Vanessa", "Mateus", "Priscila", "André", "Renata", "Diego", "Bruna"
]
sobrenomes = [
    "Cabrera", "Silva", "Oliveira", "Santos", "Souza", "Costa", "Pereira", "Ferreira",
    "Alves", "Monteiro", "Mendes", "Barros", "Freitas", "Barbosa", "Pinto", "Moura",
    "Cavalcanti", "Dias", "Castro", "Campos", "Cardoso", "Teixeira", "Ribeiro", "Vieira",
    "Rocha", "Nascimento", "Moreira", "Gomes", "Carvalho", "Lopes", "Martins", "Machado"
]
logradouros = [
    "Rua Gaspar Gomes da Costa", "Avenida Brasil", "Rua das Palmeiras", "Alameda Santos",
    "Avenida Paulista", "Rua Sete de Setembro", "Avenida Brigadeiro Faria Lima", "Rua Augusta",
    "Rua Frei Caneca", "Avenida Rio Branco", "Rua dos Três Irmãos", "Alameda Lorena",
    "Rua XV de Novembro", "Avenida Ipiranga", "Rua da Consolação", "Rua Haddock Lobo",
    "Avenida Rebouças", "Rua Oscar Freire", "Avenida Interlagos", "Rua Vergueiro",
    "Avenida Santo Amaro", "Rua Domingos de Morais", "Avenida Engenheiro Luís Carlos Berrini",
    "Rua Voluntários da Pátria", "Avenida Sumaré", "Rua Teodoro Sampaio", "Rua Cardeal Arcoverde",
    "Avenida Nove de Julho", "Rua Bela Cintra", "Avenida São João", "Alameda Campinas"
]
bairros = [
    "Cidade Nova Jacareí", "Centro", "Jardim das Flores", "Vila Olímpia",
    "Moema", "Pinheiros", "Itaim Bibi", "Brooklin",
    "Copacabana", "Ipanema", "Leblon", "Barra da Tijuca",
    "Savassi", "Lourdes", "Pampulha", "Buritis",
    "Moinhos de Vento", "Cidade Baixa", "Bom Fim", "Petrópolis",
    "Batel", "Santa Felicidade", "Água Verde", "Bigorrilho",
    "Meireles", "Aldeota", "Praia de Iracema", "Cocó",
    "Boa Viagem", "Casa Forte", "Espunheiro", "Graças"
]

def cpf_valido():
    def calculadigito(digitos):
        soma = 0
        peso = len(digitos) + 1
        for d in digitos:
            soma += int(d) * peso
            peso -= 1
        resto = soma % 11
        return 0 if resto < 2 else 11 - resto
    nove_digitos = [random.randint(0,9) for _ in range(9)]
    nove_digitos.append(calculadigito(nove_digitos))
    nove_digitos.append(calculadigito(nove_digitos))

    c = "".join(map(str, nove_digitos))
    return f"{c[:3]}.{c[3:6]}.{c[6:9]}-{c[9:]}"

def executar(total=25000):
    arquivo = 'alunos.csv'
    cabecalho = [
        "nome", "email", "telefone", "cpf", "logradouro", 
        "cep", "bairro", "numero", "cidadeId", "ufId", 
        "racaId", "generoId", "nascimento"
    ]

    print(f"Iniciando Geração de {total} registros...")

    with open(arquivo, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(cabecalho)

        for i in range(1, total + 1):
            p_nome = random.choice(nomes)
            s1, s2 = random.sample(sobrenomes, 2)
            nome_completo = f"{p_nome} {s1} {s2}"
            email = f"{p_nome.lower()}.{s1.lower()}{i}@bitfami.com"
            telefone = f"({random.randint(11, 99)}) 9{random.randint(7000, 9999)}-{random.randint(1000, 9999)}"
            cep = f"{random.randint(10000, 99999)}-{random.randint(100, 999)}"
            nascimento = f"{random.randint(1975, 2005)}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"

            writer.writerow([
                nome_completo,
                email,
                telefone,
                cpf_valido(),
                random.choice(logradouros),
                cep,
                random.choice(bairros),
                str(random.randint(1, 2500)),
                10677,
                26,
                10,
                3,
                nascimento
            ])
            if i % 500 == 0:
                print(f"{i} registros gerados...")

    print(f"\nSucesso! Arquivo '{arquivo}' criado.")
    print(f"Localização: {os.path.abspath(arquivo)}")

if __name__ == "__main__":
    executar(50000)


