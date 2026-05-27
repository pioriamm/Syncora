part of 'home_pages.dart';

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({super.key});

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage>
    with TickerProviderStateMixin {
  String _appVersion = '';
  String? _localizaName;
  String? _conexaName;
  Map<String, LocalizaRow>? _localizaRows;
  Map<String, LocalizaRow>? _localizaRowsById;
  List<ConexaRow>? _conexaRows;
  DateTime? _startDate;
  DateTime? _endDate;
  static const _apiBase = 'https://alianca.conexa.app/index.php/api/v2';
  static const _apiToken = 'a9e23e88f3283927119b49d8a8e91fd30d37cc8ea5f17b45470f23c0c10c0ae1';
  bool _loadingLocaliza = false;
  bool _loadingConexa = false;
  int _localizaCurrent = 0;
  int _localizaTotal = 0;
  int _conexaCurrent = 0;
  int _conexaTotal = 0;
  bool _loading = false;
  String _status = '';
  final TextEditingController _cnpjFilterController = TextEditingController();
  String _cnpjFilter = '';
  bool _hasError = false;
  bool _autoOpenTicketOnDueToday = false;
  DateTime? _processStart;
  Duration _processElapsed = Duration.zero;
  Timer? _processTimer;
  int _currentPage = 0;
  static const int _pageSize = 20;
  final ScrollController _resultsHorizontalScrollController =
      ScrollController();
  static const _movideskToken = '0e5c4256-d385-4ec3-a60d-b035c812ef7c';
  static const MovideskPersonInfo _fallbackMovideskPerson = MovideskPersonInfo(
    id: '43',
    businessName: 'ALIANÇA TECNOLOGIA',
    personType: 2,
    profileType: 2,
  );
  final MovideskApiService _movideskApiService = MovideskApiService();
  late final AnimationController _statusFadeController;
  late final AnimationController _statusSpinController;

  List<OutputRow> _resultRows = [];

  @override
  void initState() {
    super.initState();
    _statusFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _statusSpinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _loadAppVersion();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day);
    _loadLocalizaFromTenex();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = packageInfo.buildNumber.isNotEmpty
          ? '${packageInfo.version}+${packageInfo.buildNumber}'
          : packageInfo.version;
    });
  }



  void _loadLocalizaFromTenex() {
    final decoded = baseTenexJson;
    if (decoded is! List) return;
    final map = <String, LocalizaRow>{};
    final mapById = <String, LocalizaRow>{};
    for (final item in decoded.whereType<Map>()) {
      final idCliente = (item['id'] ?? '').toString();
      final cnpj = digitsOnly((item['cnpj'] ?? '').toString());
      if (idCliente.isEmpty && cnpj.isEmpty) continue;
      final row = LocalizaRow(
        idCliente: idCliente,
        cnpj: cnpj,
        razaoSocial: (item['razao_social'] ?? '').toString(),
        grupo: (item['grupo'] ?? '').toString(),
        vendedor: (item['vendedor'] ?? '').toString(),
        parceiro: (item['parceiro'] ?? '').toString(),
        modalidade: (item['custom_sistema'] ?? '').toString(),
      );
      if (cnpj.isNotEmpty) map[cnpj] = row;
      if (idCliente.isNotEmpty) mapById[idCliente] = row;
    }
    _localizaRows = map;
    _localizaRowsById = mapById;
  }

  Future<dynamic> _apiGet(String url) async {
    final xhr = await html.HttpRequest.request(
      url,
      method: 'GET',
      requestHeaders: {'Authorization': 'Bearer $_apiToken'},
      withCredentials: false,
    );
    if ((xhr.status ?? 0) != 200) throw Exception('API status ${xhr.status}');
    return jsonDecode(xhr.responseText ?? '[]');
  }

  ({List<dynamic> items, int? total}) _parseApiResponse(dynamic decoded) {
    if (decoded is List) return (items: decoded, total: null);
    if (decoded is Map) {
      final inner = decoded['data'] ?? decoded['items'] ?? decoded['records'] ?? decoded['result'];
      final total = decoded['totalCount'] ?? decoded['total'] ?? decoded['count'];
      return (items: inner is List ? inner : [], total: total is int ? total : null);
    }
    return (items: [], total: null);
  }

  Future<Map<String, String>> _fetchCustomerDetailsById(
      String customerId,
      ) async {
    if (customerId.trim().isEmpty) return const {};

    try {
      final decoded = await _apiGet(
        '$_apiBase/customer/$customerId',
      );

      if (decoded is! Map) return const {};

      final legalPerson = decoded['legalPerson'];

      final cnpj = legalPerson is Map
          ? (legalPerson['cnpj'] ?? '').toString()
          : '';

      final razaoSocial =
      (decoded['name'] ?? '').toString().trim();

      final emailsRaw = decoded['emailsMessage'];
      final phonesRaw = decoded['phones'];

      String email = '';
      if (emailsRaw is List && emailsRaw.isNotEmpty) {
        email = emailsRaw.first.toString();
      }

      String phone = '';
      if (phonesRaw is List && phonesRaw.isNotEmpty) {
        final first = phonesRaw.first;
        phone = first is Map
            ? (first['number'] ?? '').toString()
            : first.toString();
      }

      String vendedor = '';
      String parceiro = '';
      String sistema = '';
      String grupo = '';

      final extraFields = decoded['extraFields'];

      if (extraFields is List) {
        for (final field in extraFields.whereType<Map>()) {
          final fieldId = field['id'];
          final fieldValue =
          (field['value'] ?? '').toString();

          if (fieldId == 1) {
            vendedor = fieldValue;
          } else if (fieldId == 2) {
            parceiro = fieldValue;
          } else if (fieldId == 3) {
            sistema = fieldValue;
          } else if (fieldId == 7) {
            grupo = fieldValue;
          }
        }
      }

      return {
        'cnpj': cnpj,
        'name': razaoSocial,
        'email': email,
        'phone': phone,
        'vendedor': vendedor,
        'parceiro': parceiro,
        'sistema': sistema,
        'grupo': grupo,
      };
    } catch (e) {
      debugPrint(
        'Erro ao buscar customer $customerId: $e',
      );
      return const {};
    }
  }

  @override
  void dispose() {
    _processTimer?.cancel();
    _cnpjFilterController.dispose();
    _resultsHorizontalScrollController.dispose();
    _statusFadeController.dispose();
    _statusSpinController.dispose();
    super.dispose();
  }

  List<OutputRow> get _filteredResultRows {
    final filterText = _cnpjFilter.trim();
    final filterKey = normalizeKey(filterText);
    final filterDigits = digitsOnly(filterText);

    final rows = filterText.isEmpty
        ? _resultRows.toList()
        : () {
            final groupMatches = filterKey.isEmpty
                ? const <OutputRow>[]
                : _resultRows.where((row) {
                    final grupoKey = normalizeKey(row.grupo);
                    return grupoKey.contains(filterKey);
                  }).toList();

            if (groupMatches.isNotEmpty) {
              return groupMatches;
            }

            return _resultRows.where((row) {
              final rowDigits = digitsOnly(row.cpfCnpj);
              return filterDigits.isNotEmpty && rowDigits.contains(filterDigits);
            }).toList();
          }();

    rows.sort((a, b) {
      final aDate = _parseFlexibleDate(a.vencimento);
      final bDate = _parseFlexibleDate(b.vencimento);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });

    return rows;
  }

  void _syncStatusAnimations() {
    if (_loading) {
      if (!_statusFadeController.isAnimating) {
        _statusFadeController.repeat(reverse: true);
      }
      if (!_statusSpinController.isAnimating) {
        _statusSpinController.repeat();
      }
      return;
    }

    if (_statusFadeController.isAnimating) {
      _statusFadeController.stop();
      _statusFadeController.value = 1;
    }

    if (_statusSpinController.isAnimating) {
      _statusSpinController.stop();
      _statusSpinController.value = 0;
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatCpfCnpjForGrid(String raw) {
    final digits = digitsOnly(raw);
    if (digits.length == 14) return formattedCnpj(digits);
    return raw.trim();
  }

  String _normalizeServiceItem(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (normalizeKey(trimmed).contains('mensal')) return 'mensal';
    return trimmed;
  }

  String _formatPhoneForGrid(String value) {
    final trimmed = value.trim();
    final digits = digitsOnly(trimmed);
    if (trimmed.isEmpty || normalizeKey(trimmed) == 'null') return 'N/A';
    if (digits.isEmpty || RegExp(r'^0+$').hasMatch(digits)) return 'N/A';
    return trimmed;
  }

  Future<void> _pickFile(bool isLocaliza) async {
    if (isLocaliza) {
      setState(() {
        _loadingLocaliza = true;
        _localizaCurrent = 0;
        _localizaTotal = 0;
        _hasError = false;
        _status = 'Carregando arquivo Localiza...';
      });
    } else {
      setState(() {
        _loadingConexa = true;
        _conexaCurrent = 0;
        _conexaTotal = 0;
        _hasError = false;
        _status = 'Carregando arquivo Conexa...';
      });
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );

    if (picked == null || picked.files.isEmpty) {
      setState(() {
        _loadingLocaliza = false;
        _loadingConexa = false;
      });
      return;
    }

    final file = picked.files.first;
    if (file.bytes == null) {
      setState(() {
        _loadingLocaliza = false;
        _loadingConexa = false;
        _hasError = true;
        _status = 'Não foi possível ler o arquivo selecionado.';
      });
      return;
    }

    final isCsv = (file.extension ?? '').toLowerCase() == 'csv' ||
        file.name.toLowerCase().endsWith('.csv');

    try {
      if (isLocaliza) {
        final parsed = isCsv
            ? await parseLocalizaCsvBytes(
                file.bytes!,
                onProgress: (current, total) {
                  if (!mounted) return;
                  setState(() {
                    _localizaCurrent = current;
                    _localizaTotal = total;
                  });
                },
              )
            : await parseLocalizaBytes(
                file.bytes!,
                onProgress: (current, total) {
                  if (!mounted) return;
                  setState(() {
                    _localizaCurrent = current;
                    _localizaTotal = total;
                  });
                },
              );
        if (!mounted) return;
        setState(() {
          _localizaName = file.name;
          _localizaRows = parsed;
          _conexaName = null;
          _conexaRows = null;
          _loadingLocaliza = false;
          _status = '';
        });
      } else {
        final parsed = isCsv
            ? await parseConexaCsvBytes(
                file.bytes!,
                onProgress: (current, total) {
                  if (!mounted) return;
                  setState(() {
                    _conexaCurrent = current;
                    _conexaTotal = total;
                  });
                },
              )
            : await parseConexaBytes(
                file.bytes!,
                onProgress: (current, total) {
                  if (!mounted) return;
                  setState(() {
                    _conexaCurrent = current;
                    _conexaTotal = total;
                  });
                },
              );
        if (!mounted) return;
        setState(() {
          _conexaName = file.name;
          _conexaRows = parsed;
          _loadingConexa = false;
          _status = '';
        });
      }
    } on ProcessingException catch (e) {
      setState(() {
        _loadingLocaliza = false;
        _loadingConexa = false;
        _hasError = true;
        _status = e.message;
      });
    } catch (e, s) {
      debugPrint('Erro inesperado ao carregar planilha: $e');
      debugPrint('$s');
      setState(() {
        _loadingLocaliza = false;
        _loadingConexa = false;
        _hasError = true;
        _status = 'Erro ao ler a planilha. Verifique formato e conteúdo.';
      });
    }
  }

  Future<void> _process() async {
    if (_startDate == null || _endDate == null) {
      setState(() {
        _hasError = true;
        _status = 'Selecione data inicial e final antes de processar.';
      });
      return;
    }
    if (_localizaRows == null) {
      setState(() {
        _hasError = true;
        _status =
            'Base Tenex não carregada. Recarregue a página e tente novamente.';
      });
      return;
    }

    _processTimer?.cancel();
    _processStart = DateTime.now();
    _processElapsed = Duration.zero;
    _processTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _processStart == null) return;
      setState(() {
        _processElapsed = DateTime.now().difference(_processStart!);
      });
    });

    setState(() {
      _loading = true;
      _hasError = false;
      _status = '';
      _resultRows = [];
      _currentPage = 0;
    });

    try {
      final localizaMap = _localizaRows!;
      final localizaMapById = _localizaRowsById ?? const <String, LocalizaRow>{};
      final fetchedConexaRows = <ConexaRow>[];
      final openedTicketsByGroup = <String, MovideskTicketInfo>{};
      final groupRowsSummary = <String, List<String>>{};
      final saleNameCache = <String, String>{};
      final from = _startDate!.toIso8601String().split('T').first;
      final to = _endDate!.toIso8601String().split('T').first;
      final decoded = await _apiGet('$_apiBase/charges?status=unpaid&dueDateFrom=$from&dueDateTo=$to&limit=100');
      final chargeItems = _parseApiResponse(decoded).items;

      for (final item in chargeItems.whereType<Map>()) {
        final customerId = (item['customerId'] ?? '').toString();
        final salesIds = item['salesIds'];
        final saleIds = salesIds is List
            ? salesIds.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty)
            : const Iterable<String>.empty();
        final serviceItems = <String>{};
        for (final saleId in saleIds) {
          var saleProductName = saleNameCache[saleId] ?? '';
          if (saleProductName.isEmpty) {
            final saleDecoded = await _apiGet('$_apiBase/sale/$saleId');
            if (saleDecoded is Map) {
              saleProductName =
                  ((saleDecoded['product'] as Map?)?['name'] ?? '')
                      .toString()
                      .trim();
              if (saleProductName.isNotEmpty) {
                saleNameCache[saleId] = saleProductName;
              }
            }
          }
          if (saleProductName.isNotEmpty) {
            serviceItems.add(saleProductName);
          }
        }
        final serviceItem = serviceItems.join(' | ');
        final hasAllowedProduct = serviceItem.isNotEmpty &&
            !normalizeKey(serviceItem).contains('servico de adesao');
        if (!hasAllowedProduct) continue;

        final chargeId = (item['chargeId'] ?? item['id'] ?? '').toString();
        final localizaByCustomerId = localizaMapById[customerId];
        final cnpjFromApi = (item['cpfCnpj'] ?? item['document'] ?? '').toString();
        final razaoFromApi =
            (item['businessName'] ?? item['customerName'] ?? '').toString();
        
        final customerDetails = await _fetchCustomerDetailsById(customerId);
        
        // Prioriza Razão Social da API Conexa conforme solicitado
        final razaoSocialFinal =
        (customerDetails['name'] ?? '').trim().isNotEmpty
            ? customerDetails['name']!.trim()
            : razaoFromApi;

        final row = ConexaRow(
          idCobranca: chargeId,
          idCliente: customerId,
          cpfCnpj: (localizaByCustomerId?.cnpj ?? '').isNotEmpty
              ? localizaByCustomerId?.cnpj ?? ""
              : (customerDetails['cnpj'] ?? '').trim().isNotEmpty
                  ? customerDetails['cnpj']!
                  : cnpjFromApi,
          razaoSocialCliente: razaoSocialFinal,
          valor: (item['amount'] ?? item['value'] ?? '').toString(),
          vencimento: (item['dueDate'] ?? item['vencimento'] ?? '').toString(),
          emails: (item['email'] ?? '').toString().trim().isNotEmpty
              ? (item['email'] ?? '').toString()
              : (customerDetails['email'] ?? ''),
          telefone: (item['phone'] ?? '').toString().trim().isNotEmpty
              ? (item['phone'] ?? '').toString()
              : (customerDetails['phone'] ?? ''),
        );
        fetchedConexaRows.add(row);
        final cnpjDigits = digitsOnly(row.cpfCnpj);
        final localiza = localizaByCustomerId != null
            ? localizaByCustomerId
            : localizaMap[cnpjDigits];

        // Prioriza as informações vindas da API conforme solicitado
        final groupName = (customerDetails['grupo'] ?? '').trim().isNotEmpty 
            ? customerDetails['grupo']! 
            : (localiza?.grupo ?? '').trim();
        final vendedor =
        (customerDetails['vendedor'] ?? '').trim().isNotEmpty
            ? customerDetails['vendedor']!.trim()
            : 'N/A';
        final parceiro = (customerDetails['parceiro'] ?? '').trim().isNotEmpty 
            ? customerDetails['parceiro']! 
            : (localiza?.parceiro ?? '').trim();
        final modalidadeFromApi = (customerDetails['sistema'] ?? '').trim().isNotEmpty 
            ? customerDetails['sistema']! 
            : (localiza?.modalidade ?? '').trim();

        final groupKey = normalizeKey(groupName);
        final summary =
            '- ID: ${row.idCobranca} | Cliente: ${row.idCliente} | CNPJ: ${row.cpfCnpj} | Razão: ${row.razaoSocialCliente} | Valor: ${formatReal(row.valor)} | Vencimento: ${formatDateBr(_parseFlexibleDate(row.vencimento)) ?? row.vencimento}';
        groupRowsSummary.putIfAbsent(groupKey, () => <String>[]).add(summary);
        
        final modalidade = _resolveModalidade(modalidadeFromApi);
        final isWhiteLabel = _isWhiteLabel(modalidade);

        // Nova regra: se servicoItem for adesão -> 31
        final isAdesao = normalizeKey(serviceItem).contains('adesao');
        final regraCobranca = isAdesao ? '31' : (isWhiteLabel ? '3' : '7');

        final regraDias = int.parse(regraCobranca);
        final dataCobranca = _buildChargeDate(row.vencimento, regraDias);
        final dataCobrancaDate = dataCobranca?.date;
        final cobrar = _buildChargeLabel(dataCobrancaDate);

        final dataVencimento = _parseFlexibleDate(row.vencimento);

        // Calcula dias em atraso
        String diasAtrasoStr = '—';
        if (dataVencimento != null) {
          final today = DateTime.now();
          final todayOnly = DateTime(today.year, today.month, today.day);
          final vencimentoOnly = DateTime(dataVencimento.year, dataVencimento.month, dataVencimento.day);
          final diff = todayOnly.difference(vencimentoOnly).inDays;
          diasAtrasoStr = diff >= 0 ? diff.toString() : '0';
        }

        MovideskTicketInfo? ticketInfo = openedTicketsByGroup[groupKey];
        if (ticketInfo == null) {
          try {
            ticketInfo = await _movideskApiService.fetchTicketInfo(
              formattedCnpj(cnpjDigits),
              _movideskToken,
            );
            if (ticketInfo?.id != null) {
              openedTicketsByGroup[groupKey] = ticketInfo!;
            }
          } catch (_) {
            ticketInfo = null;
          }
        }

        final shouldCreateNewTicket =
            ticketInfo?.id == null || _isTicketClosedStatus(ticketInfo!.status);
        final isDueToday = _isToday(dataCobrancaDate);
        final isOverdueByRule = _shouldPerformCharge(dataCobrancaDate);
        final shouldOpenTicketForCharge =
            isOverdueByRule || (isDueToday && _autoOpenTicketOnDueToday);
        if (shouldOpenTicketForCharge && shouldCreateNewTicket) {
          try {
            final person = await _movideskApiService.fetchPersonByBusinessName(
                  groupName,
                  _movideskToken,
                ) ??
                _fallbackMovideskPerson;
            final formattedDocument = formattedCnpj(cnpjDigits);
            final rowsDescription = groupRowsSummary[groupKey]?.join('\n') ?? '';
            ticketInfo =
                await _movideskApiService.createOrFetchTicketAfterCreate(
                      token: _movideskToken,
                      person: person,
                      cnpj: formattedDocument,
                      razaoSocial: row.razaoSocialCliente,
                      idCobranca: row.idCobranca,
                      email: normalizeEmails(row.emails),
                      telefone: formatFirstPhone(row.telefone),
                      dataVencimento: dataVencimento,
                      actionDescription: rowsDescription.isEmpty
                          ? 'ticket criado via automação'
                          : 'ticket criado via automação\n\nLinhas do grupo:\n$rowsDescription',
                    ) ??
                    ticketInfo;
            if (ticketInfo?.id != null) {
              openedTicketsByGroup[groupKey] = ticketInfo!;
            }
          } catch (_) {
            // Evita manter referência de ticket fechado quando a reabertura falhar.
            ticketInfo = null;
          }
        }

        final output = OutputRow(
          idCobranca: row.idCobranca,
          idCliente: row.idCliente,
          cpfCnpj: _formatCpfCnpjForGrid(row.cpfCnpj),
          razaoSocialCliente: row.razaoSocialCliente,
          valor: formatReal(row.valor),
          vencimento: formatDateBr(_parseFlexibleDate(row.vencimento)) ?? row.vencimento,
          prazoCobranca: regraCobranca,
          dataCobranca: formatDateBr(dataCobrancaDate) ?? '—',
          dataCobrancaTransferida: dataCobranca?.wasTransferred ?? false,
          ticketId: ticketInfo?.id?.toString() ?? '',
          ticketStatus: ticketInfo?.status ?? '',
          ticketMovideskUrl: ticketInfo?.id == null
              ? ''
              : 'https://suporte.conciliadora.com.br/Ticket/Edit/${ticketInfo!.id}',
          grupo: groupName,
          vendedor: vendedor.trim().isEmpty ? 'N/A' : vendedor,
          parceiro: parceiro,
          modalidade: parceiro == "White Label" ? parceiro : modalidade,
          cobrar: cobrar,
          emails: normalizeEmails(row.emails),
          telefone: _formatPhoneForGrid(formatFirstPhone(row.telefone)),
          servicoItem: _normalizeServiceItem(serviceItem),
          diasAtraso: diasAtrasoStr,
        );

        if (!mounted) return;
        setState(() {
          _resultRows = [..._resultRows, output];
        });
      }

      if (!mounted) return;
      setState(() {
        _conexaRows = fetchedConexaRows;
        _conexaName = 'API Charges + Sales';
        _status = '';
      });
    } on ProcessingException catch (e) {
      setState(() {
        _hasError = true;
        _status = e.message;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _status =
            'Ocorreu um erro inesperado ao processar os arquivos. Verifique se as planilhas estão no layout correto e tente novamente.';
      });
    } finally {
      _processTimer?.cancel();
      _processTimer = null;
      if (_processStart != null) {
        _processElapsed = DateTime.now().difference(_processStart!);
      }
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool _isWhiteLabel(String modalidade) {
    return normalizeKey(modalidade).contains('whitelabel');
  }

  ChargeDateResult? _buildChargeDate(String vencimento, int graceDays) {
    final dueDate = _parseFlexibleDate(vencimento);
    if (dueDate == null) return null;
    final baseDate = dueDate.add(Duration(days: graceDays));
    return _adjustToNextBusinessDay(baseDate);
  }

  bool _shouldPerformCharge(DateTime? chargeDate) {
    if (chargeDate == null) return false;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final chargeDateOnly = DateTime(
      chargeDate.year,
      chargeDate.month,
      chargeDate.day,
    );
    return chargeDateOnly.isBefore(todayOnly);
  }

  bool _isToday(DateTime? date) {
    if (date == null) return false;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    return dateOnly == todayOnly;
  }

  String _buildChargeLabel(DateTime? chargeDate) {
    if (_shouldPerformCharge(chargeDate)) return 'Realizar cobrança';
    if (_isToday(chargeDate)) return 'Vence hoje';
    return 'No prazo';
  }

  bool _isTicketClosedStatus(String status) {
    final normalized = normalizeKey(status);
    return normalized.contains('fechado') ||
        normalized.contains('resolvido') ||
        normalized.contains('cancelado');
  }

  String _resolveModalidade(String? modalidade) {
    final value = modalidade?.trim() ?? '';
    if (value.isEmpty) {
      return 'CLIENTE FINAL';
    }

    final normalized = normalizeKey(value);
    if (normalized.contains('whitelabel')) {
      return 'WHITE LABEL';
    }

    return 'CLIENTE FINAL';
  }

  // ---------------------------------------------------------------------------
  // Export CSV
  // ---------------------------------------------------------------------------

  void _exportCsv() {
    if (_resultRows.isEmpty) return;

    String escape(String s) {
      if (s.contains('"') || s.contains(';') || s.contains('\n')) {
        final escaped = s.replaceAll('"', '""');
        return '"$escaped"';
      }
      return s;
    }

    final buf = StringBuffer();
    buf.writeln([
      'ID da Cobrança',
      'ID Cliente',
      'CPF/CNPJ',
      'Razão Social Cliente',
      'Valor',
      'Vencimento',
      'Pagamento regra',
      'Data cobrança',
      'Dias em atraso',
      'Cobrar',
      'Grupo',
      'Vendedor',
      'Parceiro',
      'Modalidade',
      'Emails',
      'Telefone',
      'Ticket',
      'Status Ticket',
      'Ticket URL',
      'Serviço/Item',
    ].map(escape).join(';'));

    for (final row in _resultRows) {
      buf.writeln([
        row.idCobranca,
        row.idCliente,
        row.cpfCnpj,
        row.razaoSocialCliente,
        row.valor,
        row.vencimento,
        row.prazoCobranca,
        row.dataCobranca,
        row.diasAtraso,
        row.cobrar,
        row.grupo,
        row.vendedor,
        row.parceiro,
        row.modalidade,
        row.emails,
        row.telefone,
        row.ticketId,
        row.ticketStatus,
        row.ticketMovideskUrl,
        row.servicoItem,
      ].map(escape).join(';'));
    }

    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(buf.toString())];
    final blob = html.Blob([Uint8List.fromList(bytes)], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'conexa_resultado.csv')
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  // ---------------------------------------------------------------------------
  // Step helpers
  // ---------------------------------------------------------------------------

  StepStatus get _localizaStatus {
    if (_loadingLocaliza) return StepStatus.carregando;
    if (_localizaRows != null) return StepStatus.pronto;
    return StepStatus.pendente;
  }

  StepStatus get _conexaStatus {
    if (_loadingConexa) return StepStatus.carregando;
    if (_conexaRows != null) return StepStatus.pronto;
    return StepStatus.pendente;
  }

  StepStatus get _processStatus {
    if (_loading) return StepStatus.processando;
    if (_resultRows.isNotEmpty && !_loading) return StepStatus.pronto;
    return StepStatus.pendente;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildIntro(),
                      const SizedBox(height: 24),
                      _buildDateRangePicker(),
                      const SizedBox(height: 16),

                      _buildStatusBar(),
                      if (_hasError && _status.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildErrorBanner(),
                      ],
                      const SizedBox(height: 24),
                      _buildResultsCard(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBadge() {
    final ready = _localizaRows != null;
    final label = ready ? 'Pronto para processar' : 'Aguardando base Tenex';
    final color = ready ? AppColors.success : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cobranças',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.4,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Selecione o período para as cobranças.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }



  Widget _buildDateRangePicker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(child: _buildDateField(isStart: true)),
          const SizedBox(width: 12),
          Expanded(child: _buildDateField(isStart: false)),
          const SizedBox(width: 20),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildDateField({required bool isStart}) {
    final date = isStart ? _startDate : _endDate;
    final label = isStart ? 'Data inicial' : 'Data final';
    final text = date == null
        ? 'Selecionar data'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    return InkWell(
      onTap: _loading ? null : () async {
        final now = DateTime.now();
        final initial = date ?? now;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2020),
          lastDate: DateTime(now.year + 1),
        );
        if (picked == null) return;
        setState(() {
          if (isStart) {
            _startDate = DateTime(picked.year, picked.month, picked.day);
            if (_endDate != null && _endDate!.isBefore(_startDate!)) {
              _endDate = _startDate;
            }
          } else {
            _endDate = DateTime(picked.year, picked.month, picked.day);
          }
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.date_range_outlined, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 220,
          height: 70,
          child: FilledButton.icon(
            onPressed: (_loading || _loadingLocaliza)
                ? null
                : _process,
            icon: const Icon(Icons.search),
            label: Text(
              _resultRows.isEmpty
                  ? 'Buscar'
                  : 'Buscar novamente',
            ),
          ),
        ),
      ],
    );
  }
  Widget _buildStepCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 820;
        final children = [
          _buildStepCard(
            stepNumber: 1,
            icon: Icons.table_view_outlined,
            title: 'Cobranças API',
            description: 'Busca automática no endpoint charges por período.',
            status: StepStatus.pronto,
            filename: _localizaName,
            count: _localizaRows?.length,
            current: _localizaCurrent,
            total: _localizaTotal,
            buttonLabel: 'Base Tenex carregada',
            onPressed: null,
          ),
          _buildStepCard(
            stepNumber: 2,
            icon: Icons.receipt_long_outlined,
            title: 'Conexa (API Sales)',
            description: 'Filtro por customerId com regra de produto.',
            status: _conexaStatus,
            filename: _conexaName,
            count: _conexaRows?.length,
            current: _conexaCurrent,
            total: _conexaTotal,
            buttonLabel: 'Consulta automática',
            onPressed: null,
            disabledHint:
                _localizaRows == null ? 'Base Tenex indisponível.' : null,
          ),
          _buildStepCard(
            stepNumber: 3,
            icon: Icons.auto_awesome_outlined,
            title: 'Processar',
            description: 'Consulta Movidesk e gera o resultado.',
            status: _processStatus,
            filename: null,
            count: _resultRows.isEmpty ? null : _resultRows.length,
            current: _resultRows.length,
            total: _conexaRows?.length ?? 0,
            buttonLabel: _resultRows.isEmpty ? 'Processar' : 'Processar novamente',
            primary: true,
            extraContent: Row(
              children: [
                Switch(
                  value: _autoOpenTicketOnDueToday,
                  activeColor: AppColors.successStrong,
                  activeTrackColor: AppColors.successStrong.withValues(alpha: 0.35),
                  thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.successStrong;
                    }
                    return null;
                  }),
                  onChanged: (value) {
                    setState(() {
                      _autoOpenTicketOnDueToday = value;
                    });
                  },
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Abrir ticket automaticamente (Vence hoje)',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            onPressed: (_loading || _loadingLocaliza || _localizaRows == null)
                ? null
                : _process,
            disabledHint: _localizaRows == null
                ? 'Base Tenex indisponível.'
                : null,
          ),
        ];

        if (isNarrow) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const SizedBox(height: 16),
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                Expanded(child: children[i]),
                if (i < children.length - 1) const SizedBox(width: 16),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepCard({
    required int stepNumber,
    required IconData icon,
    required String title,
    required String description,
    required StepStatus status,
    required String? filename,
    required int? count,
    required int current,
    required int total,
    required String buttonLabel,
    required VoidCallback? onPressed,
    Widget? extraContent,
    String? disabledHint,
    bool primary = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const Spacer(),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Passo $stepNumber',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: -0.1,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          _buildStepBody(
            status: status,
            filename: filename,
            count: count,
            current: current,
            total: total,
            disabledHint: disabledHint,
            enabled: onPressed != null,
          ),
          if (extraContent != null) ...[
            const SizedBox(height: 12),
            extraContent,
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: primary
                ? FilledButton.icon(
                    onPressed: onPressed,
                    icon: status == StepStatus.processando
                        ? _buildProcessingSpinnerIcon(
                            color: Colors.white,
                            size: 18,
                          )
                        : const Icon(Icons.play_arrow, size: 18),
                    label: Text(buttonLabel),
                  )
                : ElevatedButton.icon(
                    onPressed: onPressed,
                    icon: status == StepStatus.carregando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary),
                            ),
                          )
                        : const Icon(
                            Icons.upload_file_outlined,
                            size: 18,
                            color: AppColors.textPrimary,
                          ),
                    label: Text(buttonLabel),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepBody({
    required StepStatus status,
    required String? filename,
    required int? count,
    required int current,
    required int total,
    required String? disabledHint,
    required bool enabled,
  }) {
    if (status == StepStatus.carregando) {
      final progress = total > 0 ? (current / total).clamp(0.0, 1.0) : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.borderLight,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            total > 0
                ? 'Lendo $current de $total linhas'
                : 'Preparando arquivo...',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppColors.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    if (status == StepStatus.processando) {
      final progress = total > 0 ? (current / total).clamp(0.0, 1.0) : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.borderLight,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$current de $total processados',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppColors.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    if (status == StepStatus.pronto && filename != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                filename,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text(
                '${_formatInt(count)} linhas',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (status == StepStatus.pronto && count != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 16, color: AppColors.success),
            const SizedBox(width: 8),
            Text(
              '${_formatInt(count)} registros processados',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.success,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    // Pendente
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.borderLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.info_outline : Icons.lock_outline,
            size: 16,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              disabledHint ?? 'Nenhum arquivo selecionado.',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    _syncStatusAnimations();
    final visible = _loading ||
        (_resultRows.isNotEmpty && _processElapsed > Duration.zero);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: !visible
          ? const SizedBox.shrink()
          : Container(
              key: const ValueKey('status-bar'),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _loading
                          ? AppColors.primarySoft
                          : AppColors.successSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _loading
                        ? _buildProcessingSpinnerIcon(
                            color: AppColors.primary,
                            size: 18,
                          )
                        : const Icon(
                            Icons.task_alt_outlined,
                            color: AppColors.success,
                            size: 18,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeTransition(
                          opacity: _loading
                              ? Tween<double>(begin: 0.35, end: 1.0).animate(
                                  CurvedAnimation(
                                    parent: _statusFadeController,
                                    curve: Curves.easeInOut,
                                  ),
                                )
                              : const AlwaysStoppedAnimation<double>(1),
                          child: Text(
                            _loading
                                ? 'Processando cobranças'
                                : 'Processamento concluído',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _loading
                              ? '${_resultRows.length} de ${_conexaRows?.length ?? 0} registros'
                              : '${_resultRows.length} registros em ${_formatDuration(_processElapsed)}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          _formatDuration(_processElapsed),
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.danger,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsCard() {
    if (_resultRows.isEmpty) {
      return _buildEmptyState();
    }

    final filteredRows = _filteredResultRows;
    if (filteredRows.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0F172A),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildResultsHeader(),
            const Divider(height: 1, color: AppColors.borderLight),
            _buildFilteredEmptyState(),
          ],
        ),
      );
    }

    final totalPages = ((filteredRows.length - 1) ~/ _pageSize) + 1;
    final safePage = _currentPage.clamp(0, totalPages - 1);
    final startIdx = safePage * _pageSize;
    final endIdx = (startIdx + _pageSize) > filteredRows.length
        ? filteredRows.length
        : startIdx + _pageSize;
    final pageRows = filteredRows.sublist(startIdx, endIdx);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
            ),
          ],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResultsHeader(),
          const Divider(height: 1, color: AppColors.borderLight),
          _buildResultsTable(pageRows),
          const Divider(height: 1, color: AppColors.borderLight),
          _buildResultsFooter(
            totalCount: filteredRows.length,
            totalPages: totalPages,
            safePage: safePage,
            startIdx: startIdx,
            endIdx: endIdx,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, style: BorderStyle.solid),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: AppColors.textMuted,
              size: 22,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Nenhum resultado ainda',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Selecione o período e clique em Processar '
            'para ver os registros consolidados aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsHeader() {
    final filteredCount = _filteredResultRows.length;
    final hasFilter = _cnpjFilter.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      child: Row(
        children: [
          const Text(
            'Resultado',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Text(
              hasFilter
                  ? '${_formatInt(filteredCount)} de ${_formatInt(_resultRows.length)} registros'
                  : '${_formatInt(_resultRows.length)} registros',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _cnpjFilterController,
              cursorColor: AppColors.successStrong,
              onChanged: (value) {
                setState(() {
                  _cnpjFilter = value;
                  _currentPage = 0;
                });
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Pesquisar CNPJ ou Grupo',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _cnpjFilter.isNotEmpty
                    ? IconButton(
                        tooltip: 'Limpar pesquisa',
                        onPressed: () {
                          _cnpjFilterController.clear();
                          setState(() {
                            _cnpjFilter = '';
                            _currentPage = 0;
                          });
                        },
                        icon: const Icon(Icons.clear, size: 18),
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _loading ? null : _exportCsv,
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('Exportar CSV'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsTable(List<OutputRow> pageRows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth;
        final compact = tableWidth < 1200;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Scrollbar(
            controller: _resultsHorizontalScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            child: SingleChildScrollView(
              controller: _resultsHorizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: tableWidth),
                child: DataTable(
                headingRowColor: MaterialStateProperty.all(AppColors.surfaceAlt),
                headingTextStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
                dataTextStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                headingRowHeight: 44,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 56,
                horizontalMargin: compact ? 10 : 16,
                columnSpacing: compact ? 16 : 22,
                dividerThickness: 1,
                columns: const [
                  DataColumn(label: Text('ID COBRANÇA')),
                  DataColumn(label: Text('ID CLIENTE')),
                  DataColumn(label: Text('CPF/CNPJ')),
                  DataColumn(label: Text('RAZÃO SOCIAL')),
                  DataColumn(label: Text('VALOR'), numeric: true),
                  DataColumn(label: Text('VENCIMENTO')),
                  DataColumn(label: Text('DIAS ATRASO'), numeric: true),
                  DataColumn(label: Text('REGRA')),
                  DataColumn(label: Text('DATA COBRANÇA')),
                  DataColumn(label: Text('COBRAR')),
                  DataColumn(label: Text('GRUPO')),
                  DataColumn(label: Text('VENDEDOR')),
                  DataColumn(label: Text('PARCEIRO')),
                  DataColumn(label: Text('MODALIDADE')),
                  DataColumn(label: Text('EMAILS')),
                  DataColumn(label: Text('TELEFONE')),
                  DataColumn(label: Text('SERVIÇO/ITEM')),
                  DataColumn(label: Text('TICKET')),
                ],
                  rows: List.generate(pageRows.length, (index) {
                final row = pageRows[index];
                final zebra = index.isOdd;
                return DataRow(
                  color: MaterialStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(MaterialState.hovered)) {
                      return AppColors.primarySoft.withOpacity(0.25);
                    }
                    return zebra ? AppColors.surfaceAlt.withOpacity(0.5) : null;
                  }),
                  cells: [
                    _buildCopyableDataCell(
                      valueToCopy: row.idCobranca,
                      child: Text(
                        row.idCobranca,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.idCliente,
                      child: Text(
                        row.idCliente,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.cpfCnpj,
                      child: Text(
                        row.cpfCnpj,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.razaoSocialCliente,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: compact ? 180 : 260,
                        ),
                        child: Text(
                          row.razaoSocialCliente,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.valor,
                      child: Text(
                        row.valor,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.vencimento,
                      child: Text(
                        row.vencimento,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.diasAtraso,
                      child: Text(
                        row.diasAtraso,
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: (int.tryParse(row.diasAtraso) ?? 0) > 0 
                              ? AppColors.danger 
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.prazoCobranca,
                      child: _RegraBadge(value: row.prazoCobranca),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.dataCobranca,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            row.dataCobranca,
                            style: TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 13,
                              color: row.cobrar == 'Vence hoje'
                                  ? AppColors.warning
                                  : AppColors.textSecondary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (row.dataCobrancaTransferida) ...[
                            const SizedBox(width: 6),
                            const Tooltip(
                              message: 'transferida para o próximo dia util',
                              child: Icon(
                                Icons.info_outline,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.cobrar,
                      child: _CobrarBadge(value: row.cobrar),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.grupo,
                      child: _GrupoChip(value: row.grupo),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.vendedor,
                      child: Text(
                        row.vendedor,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.parceiro,
                      child: Text(
                        row.parceiro,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.modalidade,
                      child: Text(
                        row.modalidade,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.emails,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: compact ? 180 : 240,
                        ),
                        child: Text(
                          row.emails,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.telefone,
                      child: Text(
                        row.telefone,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.servicoItem,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: compact ? 180 : 240,
                        ),
                        child: Text(
                          row.servicoItem,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    _buildCopyableDataCell(
                      valueToCopy: row.ticketId,
                      child: _TicketCell(
                        ticketId: row.ticketId,
                        ticketStatus: row.ticketStatus,
                      ),
                      onTap: () => _openTicketLink(row.ticketMovideskUrl),
                    ),
                  ],
                );
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  DataCell _buildCopyableDataCell({
    required Widget child,
    required String valueToCopy,
    VoidCallback? onTap,
  }) {
    return DataCell(
      child,
      onTap: onTap ?? () => _copyCellValue(valueToCopy),
    );
  }

  void _openTicketLink(String url) {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) return;
    html.window.open(normalizedUrl, '_blank');
  }

  Future<void> _copyCellValue(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    final preview = value.trim().isEmpty ? '(vazio)' : value;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Conteúdo copiado: ${preview.length > 70 ? '${preview.substring(0, 67)}...' : preview}',
          ),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  Widget _buildProcessingSpinnerIcon({
    required Color color,
    required double size,
  }) {
    return AnimatedBuilder(
      animation: _statusSpinController,
      child: Icon(
        Icons.sync,
        color: color,
        size: size,
      ),
      builder: (context, child) {
        return Transform.rotate(
          angle: _statusSpinController.value * 2 * math.pi,
          child: child,
        );
      },
    );
  }

  Widget _buildResultsFooter({
    required int totalCount,
    required int totalPages,
    required int safePage,
    required int startIdx,
    required int endIdx,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Row(
        children: [
          Text(
            'Mostrando ${startIdx + 1}–$endIdx de ${_formatInt(totalCount)}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppColors.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          _PageIconButton(
            tooltip: 'Primeira página',
            icon: Icons.first_page,
            onPressed:
                safePage > 0 ? () => setState(() => _currentPage = 0) : null,
          ),
          _PageIconButton(
            tooltip: 'Página anterior',
            icon: Icons.chevron_left,
            onPressed: safePage > 0
                ? () => setState(() => _currentPage = safePage - 1)
                : null,
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Text(
              'Página ${safePage + 1} de $totalPages',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _PageIconButton(
            tooltip: 'Próxima página',
            icon: Icons.chevron_right,
            onPressed: safePage < totalPages - 1
                ? () => setState(() => _currentPage = safePage + 1)
                : null,
          ),
          _PageIconButton(
            tooltip: 'Última página',
            icon: Icons.last_page,
            onPressed: safePage < totalPages - 1
                ? () => setState(() => _currentPage = totalPages - 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 30, color: AppColors.textMuted),
          const SizedBox(height: 12),
          const Text(
            'Nenhum resultado encontrado',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ajuste o termo digitado no campo de pesquisa para ver os resultados.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  String _formatInt(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
