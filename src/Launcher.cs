// Inicializador da tradução: extrai o script e o dicionário embutidos para a pasta de dados de quem
// usa e roda o Windows PowerShell. Sem dependência além do .NET Framework que vem no Windows.
//
// Etapa elevada: nada da pasta do usuário é executado nem lido como administrador. O próprio exe se
// reabre elevado, extrai script e dicionário numa pasta nova, só de administradores, confere o hash
// de cada arquivo contra o recurso embutido e só então roda. Dados da etapa elevada (backup e estado)
// ficam numa pasta em que só administradores gravam.
//
// O símbolo SIMULAR_UAC só existe na compilação de teste (scripts\build.ps1 -SimularUac): troca o
// pedido real de administrador por uma execução comum, para testar o caminho inteiro sem o aviso do
// Windows. Nada disso entra no executável publicado.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;

internal static class Launcher
{
    private const string PrefixoRecurso = "app/";
    private const string Script = "titanfall-ptbr.ps1";
    private const string ArgumentoElevado = "--elevado";
    private const string ArquivoPedido = "pedido-elevacao.txt";
    private const int CodigoPedeElevacao = 20;
    private const int CodigoSemPermissao = 3;
    private const int ErroCanceladoPeloUsuario = 1223;
    // Escrita, permissões e dono, além de GENERIC_ALL e GENERIC_WRITE.
    private const int DireitosDeEscrita = (int)(FileSystemRights.WriteData | FileSystemRights.AppendData
        | FileSystemRights.WriteExtendedAttributes | FileSystemRights.WriteAttributes | FileSystemRights.Delete
        | FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership) | 0x50000000;

    private static int Main(string[] args)
    {
        bool elevado = args.Length > 0 && args[0] == ArgumentoElevado;
        try
        {
            return elevado ? EtapaElevada(args) : EtapaComum(args);
        }
        catch (Exception erro)
        {
            Console.Error.WriteLine("Nao consegui iniciar a ferramenta: " + erro.Message);
            if (args.Length == 0 || elevado)
            {
                Console.Error.WriteLine("Aperte Enter para fechar.");
                Console.ReadLine();
            }
            return 1;
        }
    }

    private static int EtapaComum(string[] args)
    {
        string dados = PastaDados(args);
        string versao = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
        string app = Path.Combine(Path.Combine(dados, "app"), versao);
        Extrair(app);
        LimparVersoesAntigas(Path.Combine(dados, "app"), versao);

        bool menu = !TemArgumento(args, "-Acao");
        while (true)
        {
            int codigo = RodarComum(Path.Combine(app, Script), dados, args);
            if (codigo != CodigoPedeElevacao)
            {
                return codigo;
            }
            int elevado = PedirElevacao(dados);
            if (!menu)
            {
                return elevado;
            }
        }
    }

    private static string PastaDados(string[] args)
    {
        for (int i = 0; i + 1 < args.Length; i++)
        {
            if (string.Equals(args[i], "-PastaDados", StringComparison.OrdinalIgnoreCase))
            {
                return Path.GetFullPath(args[i + 1]);
            }
        }
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(Path.Combine(local, "ScarletModder"), "Titanfall2VR-PTBR");
    }

    private static string RaizAdmin()
    {
#if SIMULAR_UAC
        return Path.Combine(Environment.GetEnvironmentVariable("TF2VR_TESTE_RAIZ"), "ScarletModder");
#else
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "ScarletModder");
#endif
    }

    private static string PastaDadosAdmin()
    {
        return Path.Combine(RaizAdmin(), "Titanfall2VR-PTBR");
    }

    private static Dictionary<string, byte[]> Recursos()
    {
        Dictionary<string, byte[]> recursos = new Dictionary<string, byte[]>();
        Assembly assembly = Assembly.GetExecutingAssembly();
        foreach (string nome in assembly.GetManifestResourceNames())
        {
            if (!nome.StartsWith(PrefixoRecurso, StringComparison.Ordinal))
            {
                continue;
            }
            string relativo = nome.Substring(PrefixoRecurso.Length).Replace('/', Path.DirectorySeparatorChar);
            using (Stream origem = assembly.GetManifestResourceStream(nome))
            using (MemoryStream memoria = new MemoryStream())
            {
                origem.CopyTo(memoria);
                recursos[relativo] = memoria.ToArray();
            }
        }
        return recursos;
    }

    private static void Extrair(string destino)
    {
        foreach (KeyValuePair<string, byte[]> recurso in Recursos())
        {
            string caminho = Path.Combine(destino, recurso.Key);
            if (File.Exists(caminho) && MesmoConteudo(File.ReadAllBytes(caminho), recurso.Value))
            {
                continue;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(caminho));
            File.WriteAllBytes(caminho, recurso.Value);
        }
    }

    private static void Verificar(string destino)
    {
        Dictionary<string, byte[]> recursos = Recursos();
        foreach (KeyValuePair<string, byte[]> recurso in recursos)
        {
            string caminho = Path.Combine(destino, recurso.Key);
            if (!File.Exists(caminho) || !MesmoConteudo(File.ReadAllBytes(caminho), recurso.Value))
            {
                throw new InvalidOperationException("o arquivo extraido nao confere com o executavel: " + recurso.Key);
            }
        }
        if (Directory.GetFiles(destino, "*", SearchOption.AllDirectories).Length != recursos.Count)
        {
            throw new InvalidOperationException("a pasta extraida tem arquivos a mais");
        }
    }

    private static bool MesmoConteudo(byte[] a, byte[] b)
    {
        using (SHA256 sha = SHA256.Create())
        {
            return Convert.ToBase64String(sha.ComputeHash(a)) == Convert.ToBase64String(sha.ComputeHash(b));
        }
    }

    // Só apaga subpasta com nome de versão: -PastaDados pode apontar para uma pasta que já tem um app próprio.
    private static void LimparVersoesAntigas(string raiz, string atual)
    {
        try
        {
            foreach (string pasta in Directory.GetDirectories(raiz))
            {
                string nome = Path.GetFileName(pasta);
                if (Regex.IsMatch(nome, @"^\d+\.\d+\.\d+$") && !string.Equals(nome, atual, StringComparison.OrdinalIgnoreCase))
                {
                    ApagarSemSeguir(pasta);
                }
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static bool EhLink(string caminho)
    {
        return (File.GetAttributes(caminho) & FileAttributes.ReparsePoint) != 0;
    }

    // Apaga a pasta sem nunca entrar em junction ou link simbólico: some o link, o destino fica.
    private static void ApagarSemSeguir(string pasta)
    {
        if (!EhLink(pasta))
        {
            foreach (string arquivo in Directory.GetFiles(pasta))
            {
                if (!EhLink(arquivo))
                {
                    File.SetAttributes(arquivo, FileAttributes.Normal);
                }
                File.Delete(arquivo);
            }
            foreach (string filha in Directory.GetDirectories(pasta))
            {
                ApagarSemSeguir(filha);
            }
        }
        Directory.Delete(pasta, false);
    }

    private static int RodarComum(string script, string dados, string[] args)
    {
        List<string> argumentos = new List<string>();
        argumentos.AddRange(new string[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script });
        argumentos.AddRange(args);
        if (!TemArgumento(args, "-PastaDados"))
        {
            argumentos.Add("-PastaDados");
            argumentos.Add(dados);
        }
        if (!TemArgumento(args, "-PastaDadosAdmin"))
        {
            argumentos.Add("-PastaDadosAdmin");
            argumentos.Add(PastaDadosAdmin());
        }
        argumentos.Add("-ViaExe");
        return RodarPowerShell(argumentos, null);
    }

    private static int RodarPowerShell(List<string> argumentos, string pastaDeTrabalho)
    {
        string sistema = Environment.GetFolderPath(Environment.SpecialFolder.System);
        string powershell = Path.Combine(sistema, @"WindowsPowerShell\v1.0\powershell.exe");
        ProcessStartInfo inicio = new ProcessStartInfo(powershell, Juntar(argumentos));
        inicio.UseShellExecute = false;
        // Aberto a partir do PowerShell 7, o exe herdaria módulos que o Windows PowerShell não carrega.
        inicio.EnvironmentVariables.Remove("PSModulePath");
        if (pastaDeTrabalho != null)
        {
            inicio.WorkingDirectory = pastaDeTrabalho;
        }
        using (Process processo = Process.Start(inicio))
        {
            processo.WaitForExit();
            return processo.ExitCode;
        }
    }

    // O script comum diz o que precisa de permissão; aqui o exe se reabre como administrador.
    private static int PedirElevacao(string dados)
    {
        string arquivo = Path.Combine(dados, ArquivoPedido);
        string[] pedido = File.ReadAllLines(arquivo, new UTF8Encoding(false));
        File.Delete(arquivo);
        if (pedido.Length < 2)
        {
            throw new InvalidOperationException("pedido de permissao incompleto");
        }
        List<string> argumentos = new List<string>(new string[] { ArgumentoElevado, pedido[0], pedido[1] });
        ProcessStartInfo inicio = new ProcessStartInfo(Assembly.GetExecutingAssembly().Location, Juntar(argumentos));
#if SIMULAR_UAC
        inicio.UseShellExecute = false;
        if (Environment.GetEnvironmentVariable("TF2VR_TESTE_RECUSAR") == "1")
        {
            Console.WriteLine("A permissao de administrador foi recusada. Nada foi alterado.");
            return CodigoSemPermissao;
        }
#else
        inicio.UseShellExecute = true;
        inicio.Verb = "runas";
#endif
        try
        {
            using (Process processo = Process.Start(inicio))
            {
                processo.WaitForExit();
                return processo.ExitCode;
            }
        }
        catch (Win32Exception erro)
        {
            if (erro.NativeErrorCode != ErroCanceladoPeloUsuario)
            {
                throw;
            }
            Console.WriteLine("A permissao de administrador foi recusada. Nada foi alterado.");
            return CodigoSemPermissao;
        }
    }

    private static int EtapaElevada(string[] args)
    {
        if (args.Length != 3 || (args[1] != "Traduzir" && args[1] != "Restaurar"))
        {
            throw new ArgumentException("pedido de permissao invalido");
        }
        if (!SouAdministrador())
        {
            throw new UnauthorizedAccessException("esta etapa so roda como administrador");
        }
        string jogo = args[2];
        if (!File.Exists(Path.Combine(jogo, "Titanfall2.exe")))
        {
            throw new ArgumentException("a pasta informada nao tem o Titanfall2.exe");
        }
#if SIMULAR_UAC
        foreach (string arquivo in Directory.GetFiles(jogo, "*", SearchOption.AllDirectories))
        {
            File.SetAttributes(arquivo, FileAttributes.Normal);
        }
#endif
        PastaSoDeAdministradores(RaizAdmin(), true);
        LimparExecucoesAntigas();
        string dados = PastaDadosAdmin();
        PastaSoDeAdministradores(dados, true);
        string execucao = Path.Combine(RaizAdmin(), "run-" + Guid.NewGuid().ToString("N"));
        PastaSoDeAdministradores(execucao, false);
        try
        {
            Extrair(execucao);
#if SIMULAR_UAC
            if (Environment.GetEnvironmentVariable("TF2VR_TESTE_ADULTERAR") == "1")
            {
                File.AppendAllText(Path.Combine(execucao, Script), "# adulterado");
            }
#endif
            Verificar(execucao);
            List<string> argumentos = new List<string>(new string[] {
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(execucao, Script),
                "-Acao", args[1], "-PastaJogo", jogo, "-PastaDados", dados, "-Elevado" });
#if !SIMULAR_UAC
            argumentos.Add("-Pausar");
#endif
            return RodarPowerShell(argumentos, execucao);
        }
        finally
        {
            ConsolidarDono(dados);
            try
            {
                ApagarSemSeguir(execucao);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    // Janela fechada no meio deixa a pasta de execução para trás; a próxima etapa elevada limpa.
    private static void LimparExecucoesAntigas()
    {
        foreach (string velha in Directory.GetDirectories(RaizAdmin(), "run-*"))
        {
            try
            {
                if (EntradaConfiavel(velha))
                {
                    ApagarSemSeguir(velha);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    // Conforme a política do Windows, o dono do que o script cria pode ser a conta, e não o grupo de
    // administradores. A próxima etapa elevada recusaria esses arquivos, então o dono é acertado aqui.
    private static void ConsolidarDono(string dados)
    {
#if !SIMULAR_UAC
        try
        {
            SecurityIdentifier administradores = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            foreach (string entrada in Directory.GetFileSystemEntries(dados))
            {
                if (EhLink(entrada))
                {
                    continue;
                }
                if (Directory.Exists(entrada))
                {
                    DirectorySecurity dono = new DirectorySecurity();
                    dono.SetOwner(administradores);
                    Directory.SetAccessControl(entrada, dono);
                }
                else
                {
                    FileSecurity dono = new FileSecurity();
                    dono.SetOwner(administradores);
                    File.SetAccessControl(entrada, dono);
                }
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
#endif
    }

    private static bool SouAdministrador()
    {
#if SIMULAR_UAC
        return true;
#else
        using (WindowsIdentity identidade = WindowsIdentity.GetCurrent())
        {
            return new WindowsPrincipal(identidade).IsInRole(WindowsBuiltInRole.Administrator);
        }
#endif
    }

    // Pasta com herança desligada: só administradores e o sistema gravam. Pasta de antes que não seja
    // de um deles, ou que seja um link, pode ter sido preparada por um processo comum e é descartada.
    private static void PastaSoDeAdministradores(string pasta, bool usuariosLeem)
    {
        SecurityIdentifier administradores = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        SecurityIdentifier sistema = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        if (Directory.Exists(pasta) && !EntradaConfiavel(pasta))
        {
            ApagarSemSeguir(pasta);
        }
        DirectorySecurity seguranca = new DirectorySecurity();
        seguranca.SetAccessRuleProtection(true, false);
        Permitir(seguranca, administradores, FileSystemRights.FullControl);
        Permitir(seguranca, sistema, FileSystemRights.FullControl);
        if (usuariosLeem)
        {
            Permitir(seguranca, new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null), FileSystemRights.ReadAndExecute);
        }
#if SIMULAR_UAC
        using (WindowsIdentity identidade = WindowsIdentity.GetCurrent())
        {
            Permitir(seguranca, identidade.User, FileSystemRights.FullControl);
        }
        Directory.CreateDirectory(pasta);
        Directory.SetAccessControl(pasta, seguranca);
        Console.WriteLine("acl " + Path.GetFileName(pasta) + " " + Directory.GetAccessControl(pasta).GetSecurityDescriptorSddlForm(AccessControlSections.Access));
#else
        seguranca.SetOwner(administradores);
        Directory.CreateDirectory(pasta, seguranca);
        Directory.SetAccessControl(pasta, seguranca);
#endif
        // Janela fechada no meio não passa pelo finally: o dono dos arquivos já guardados é acertado aqui.
        ConsolidarDono(pasta);
        Revalidar(pasta);
    }

    // Entre apagar e criar, outro processo pode ter recriado a pasta. Só segue se ela e os filhos diretos
    // estiverem certos agora; do contrário, nada roda.
    private static void Revalidar(string pasta)
    {
        if (!EntradaConfiavel(pasta) || !Directory.GetAccessControl(pasta).AreAccessRulesProtected)
        {
            throw new InvalidOperationException("a pasta de administradores nao e confiavel: " + Path.GetFileName(pasta));
        }
        foreach (string entrada in Directory.GetFileSystemEntries(pasta))
        {
            if (!EntradaConfiavel(entrada))
            {
                throw new InvalidOperationException("a pasta de administradores nao e confiavel: " + Path.GetFileName(entrada));
            }
        }
    }

    private static void Permitir(DirectorySecurity seguranca, IdentityReference quem, FileSystemRights direitos)
    {
        seguranca.AddAccessRule(new FileSystemAccessRule(quem, direitos,
            InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
    }

    // Confiável: não é link, tem dono administrador ou sistema, e só eles têm direito de escrita.
    private static bool EntradaConfiavel(string caminho)
    {
        if (EhLink(caminho))
        {
            return false;
        }
        FileSystemSecurity seguranca;
        if (Directory.Exists(caminho))
        {
            seguranca = Directory.GetAccessControl(caminho, AccessControlSections.Owner | AccessControlSections.Access);
        }
        else
        {
            seguranca = File.GetAccessControl(caminho, AccessControlSections.Owner | AccessControlSections.Access);
        }
#if !SIMULAR_UAC
        if (!PodeEscrever(seguranca.GetOwner(typeof(SecurityIdentifier))))
        {
            return false;
        }
#endif
        foreach (FileSystemAccessRule regra in seguranca.GetAccessRules(true, true, typeof(SecurityIdentifier)))
        {
            if (regra.AccessControlType == AccessControlType.Allow && (((int)regra.FileSystemRights) & DireitosDeEscrita) != 0 && !PodeEscrever(regra.IdentityReference))
            {
                return false;
            }
        }
        return true;
    }

    private static bool PodeEscrever(IdentityReference quem)
    {
        SecurityIdentifier sid = quem as SecurityIdentifier;
        if (sid == null)
        {
            return false;
        }
#if SIMULAR_UAC
        using (WindowsIdentity identidade = WindowsIdentity.GetCurrent())
        {
            if (sid.Equals(identidade.User))
            {
                return true;
            }
        }
#endif
        return sid.IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid) || sid.IsWellKnown(WellKnownSidType.LocalSystemSid);
    }

    private static bool TemArgumento(string[] args, string nome)
    {
        foreach (string a in args)
        {
            if (string.Equals(a, nome, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static string Juntar(IEnumerable<string> argumentos)
    {
        StringBuilder linha = new StringBuilder();
        foreach (string a in argumentos)
        {
            if (linha.Length > 0)
            {
                linha.Append(' ');
            }
            linha.Append(Citar(a));
        }
        return linha.ToString();
    }

    // Regras de citação de linha de comando do Windows: barras antes de aspas dobram.
    private static string Citar(string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0)
        {
            return a;
        }
        StringBuilder saida = new StringBuilder("\"");
        int barras = 0;
        foreach (char c in a)
        {
            if (c == '\\')
            {
                barras++;
                continue;
            }
            saida.Append('\\', c == '"' ? barras * 2 + 1 : barras);
            barras = 0;
            saida.Append(c);
        }
        saida.Append('\\', barras * 2);
        saida.Append('"');
        return saida.ToString();
    }
}
